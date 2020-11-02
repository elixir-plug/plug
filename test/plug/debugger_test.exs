defmodule Plug.DebuggerTest do
  use ExUnit.Case, async: true
  use Plug.Test

  import ExUnit.CaptureLog

  defmodule Exception do
    defexception plug_status: 403, message: "oops"
  end

  defmodule ActionableError do
    defexception message: "Actionable Exception Error"
  end

  defimpl Plug.Exception, for: ActionableError do
    def status(_), do: 418

    def actions(_),
      do: [%{label: "Send message", handler: {Process, :send, [self(), :actionable_error, []]}}]
  end

  defmodule Router do
    use Plug.Router
    use Plug.Debugger, otp_app: :plug

    plug :add_csp

    plug :match
    plug :dispatch

    def call(conn, opts) do
      if conn.path_info == ~w(boom) do
        raise "<oops>"
      else
        super(conn, opts)
      end
    end

    get "/nil" do
      _ = conn
      returns_nil().id()
    end

    get "/soft_boom" do
      _ = conn
      raise Exception
    end

    get "/send_and_boom" do
      send_resp(conn, 200, "oops")
      raise "oops"
    end

    get "/send_and_wrapped" do
      stack =
        try do
          raise "oops"
        rescue
          _ -> __STACKTRACE__
        end

      raise Plug.Conn.WrapperError,
        conn: conn,
        kind: :error,
        stack: stack,
        reason: Exception.exception([])
    end

    match "/actionable_exception" do
      _ = conn
      raise ActionableError
    end

    defp returns_nil, do: nil

    defp add_csp(conn, _opts),
      do: Plug.Conn.put_resp_header(conn, "content-security-policy", "abcdef")
  end

  defmodule StyledRouter do
    use Plug.Router

    use Plug.Debugger,
      style: [primary: "#c0ffee", logo: nil],
      banner: {__MODULE__, :banner, []}

    plug :match
    plug :dispatch

    get "/boom" do
      _ = conn
      raise "oops"
    end

    def banner(%Plug.Conn{}, status, kind, reason, [_ | _] = _stack) do
      "<h1>#{inspect(status)}, #{inspect(kind)}, #{inspect(reason)}</h1>"
    end
  end

  test "call/2 is overridden" do
    conn = put_req_header(conn(:get, "/boom"), "accept", "text/html")

    assert_raise RuntimeError, "<oops>", fn ->
      Router.call(conn, [])
    end

    assert_received {:plug_conn, :sent}
    {status, headers, body} = sent_resp(conn)
    assert status == 500

    assert List.keyfind(headers, "content-type", 0) ==
             {"content-type", "text/html; charset=utf-8"}

    assert body =~ "<title>RuntimeError at GET /boom</title>"
    assert body =~ "&lt;oops&gt;"
  end

  test "call/2 is overridden and warns on non-500 errors" do
    conn = put_req_header(conn(:get, "/soft_boom"), "accept", "text/html")

    capture_log(fn ->
      assert_raise Exception, fn ->
        Router.call(conn, [])
      end
    end)

    assert_received {:plug_conn, :sent}
    {status, headers, body} = sent_resp(conn)
    assert status == 403

    assert List.keyfind(headers, "content-type", 0) ==
             {"content-type", "text/html; charset=utf-8"}

    assert body =~ "<title>Plug.DebuggerTest.Exception at GET /soft_boom</title>"
    assert body =~ "oops"
  end

  test "call/2 is overridden but is a no-op when response is already sent" do
    conn = put_req_header(conn(:get, "/send_and_boom"), "accept", "text/html")

    capture_log(fn ->
      assert_raise RuntimeError, "oops", fn ->
        Router.call(conn, [])
      end
    end)

    assert_received {:plug_conn, :sent}
    assert {200, _headers, "oops"} = sent_resp(conn)
  end

  test "call/2 is overridden and unwrapps wrapped errors" do
    conn = put_req_header(conn(:get, "/send_and_wrapped"), "accept", "text/html")

    capture_log(fn ->
      assert_raise Exception, "oops", fn ->
        Router.call(conn, [])
      end
    end)

    assert_received {:plug_conn, :sent}
    {status, headers, body} = sent_resp(conn)
    assert status == 403

    assert List.keyfind(headers, "content-type", 0) ==
             {"content-type", "text/html; charset=utf-8"}

    refute List.keymember?(headers, "content-security-policy", 0)

    assert body =~ "<title>Plug.DebuggerTest.Exception at GET /send_and_wrapped</title>"
  end

  test "call/2 is overridden and handles errors without sources" do
    conn = put_req_header(conn(:get, "/nil"), "accept", "text/html")

    capture_log(fn ->
      assert_raise UndefinedFunctionError, fn ->
        Router.call(conn, [])
      end
    end)

    assert_received {:plug_conn, :sent}
    {status, headers, body} = sent_resp(conn)
    assert status == 500

    assert List.keyfind(headers, "content-type", 0) ==
             {"content-type", "text/html; charset=utf-8"}

    assert body =~ "<title>UndefinedFunctionError at GET /nil</title>"
  end

  defp render(conn, opts, fun) do
    opts =
      opts
      |> Keyword.put_new(:stack, [])
      |> Keyword.put_new(:otp_app, :plug)

    try do
      fun.()
    catch
      kind, reason ->
        Plug.Debugger.render(conn, 500, kind, reason, opts[:stack], opts)
    else
      _ -> flunk("function should have failed")
    end
  end

  test "exception page for throws" do
    conn = render(conn(:get, "/"), [], fn -> throw(:hello) end)

    assert conn.status == 500
    assert conn.resp_body =~ "unhandled throw at GET /"
    assert conn.resp_body =~ ":hello"
  end

  test "exception page for exceptions" do
    conn =
      render(conn(:get, "/"), [], fn ->
        raise Plug.Parsers.UnsupportedMediaTypeError, media_type: "foo/bar"
      end)

    assert conn.resp_body =~ "Plug.Parsers.UnsupportedMediaTypeError"
    assert conn.resp_body =~ "at GET /"
    assert conn.resp_body =~ "unsupported media type foo/bar"
  end

  test "exception page for exits" do
    conn =
      render(conn(:get, "/"), [], fn ->
        exit({:timedout, {GenServer, :call, [:foo, :bar]}})
      end)

    assert conn.resp_body =~ "unhandled exit at GET /"
    assert conn.resp_body =~ "exited in: GenServer.call(:foo, :bar)"
  end

  test "shows request info" do
    conn =
      conn(:get, "/foo/bar?baz=bat")
      |> put_req_header("accept", "text/html")
      |> render([], fn -> raise "oops" end)

    assert conn.resp_body =~ "<summary>Request info</summary>"
    assert conn.resp_body =~ "http://www.example.com:80/foo/bar"
    assert conn.resp_body =~ "baz=bat"
  end

  test "shows headers" do
    conn =
      conn(:get, "/foo/bar?baz=bat", [])
      |> put_req_header("my-header", "my-value")
      |> put_req_header("accept", "text/html")
      |> render([], fn -> raise "oops" end)

    assert conn.resp_body =~ "<summary>Headers</summary>"
    assert conn.resp_body =~ "my-header"
    assert conn.resp_body =~ "my-value"
  end

  test "shows params" do
    conn =
      conn(:get, "/foo/bar?from-qs-key=from-qs-value", %{"from-body-key" => "from-body-value"})
      |> put_req_header("accept", "text/html")
      |> Plug.Parsers.call(Plug.Parsers.init(parsers: [:urlencoded]))
      |> render([], fn -> raise "oops" end)

    assert conn.resp_body =~ "<summary>Params</summary>"
    assert conn.resp_body =~ "from-qs-key"
    assert conn.resp_body =~ "from-qs-value"
    assert conn.resp_body =~ "from-body-key"
    assert conn.resp_body =~ "from-body-value"
  end

  test "shows no query params on bad query string" do
    conn = render(conn(:get, "/foo/bar?q=%{"), [], fn -> raise "oops" end)
    assert conn.resp_body =~ "RuntimeError"
    assert conn.resp_body =~ "at GET /foo/bar"
    assert conn.resp_body =~ "oops"
    refute conn.resp_body =~ "<summary>Params</summary>"
  end

  test "shows session" do
    Process.put({:session, "sid"}, %{session_key: "session_value"})

    conn =
      conn(:get, "/foo/bar")
      |> put_req_header("accept", "text/html")
      |> fetch_cookies
      |> (&put_in(&1.cookies["foobar"], "sid")).()
      |> Plug.Session.call(Plug.Session.init(store: Plug.ProcessStore, key: "foobar"))
      |> render([], fn -> raise "oops" end)

    assert conn.resp_body =~ "<summary>Session</summary>"
    assert conn.resp_body =~ "session_key"
    assert conn.resp_body =~ "session_value"
  end

  defp stack(stack) do
    render(put_req_header(conn(:get, "/"), "accept", "text/html"), [stack: stack], fn ->
      raise "oops"
    end)
  end

  test "sanitizes output" do
    conn =
      conn(:get, "/foo/bar?x=<script>alert(document.domain)</script>")
      |> put_req_header("accept", "text/html")
      |> Plug.Parsers.call(Plug.Parsers.init(parsers: [:urlencoded]))
      |> put_req_header("<script>xss-header</script>", "<script>xss-val</script>")
      |> render([], fn -> raise "<script>oops</script>" end)

    assert conn.resp_body =~ "x=&lt;script&gt;alert(document.domain)&lt;/script&gt;"
    assert conn.resp_body =~ "&lt;script&gt;xss-header&lt;/script&gt;"
    assert conn.resp_body =~ "&lt;script&gt;xss-val&lt;/script&gt;"
    assert conn.resp_body =~ "&lt;script&gt;oops&lt;/script&gt;"
  end

  test "uses PLUG_EDITOR" do
    System.put_env("PLUG_EDITOR", "hello://open?file=__FILE__&line=__LINE__")

    conn = stack([{Plug.Conn, :unknown, 1, file: "lib/plug/conn.ex", line: 1}])
    file = Path.expand("lib/plug/conn.ex")
    assert conn.resp_body =~ "hello://open?file=#{file}&amp;line=1"

    conn = stack([{GenServer, :call, 2, file: "lib/gen_server.ex", line: 10_000}])
    file = Path.expand(GenServer.__info__(:compile)[:source])
    assert conn.resp_body =~ "hello://open?file=#{file}&amp;line=10000"
  end

  test "styles can be overridden" do
    conn = put_req_header(conn(:get, "/boom"), "accept", "text/html")

    assert_raise RuntimeError, fn ->
      StyledRouter.call(conn, [])
    end

    {_status, _headers, body} = sent_resp(conn)
    assert body =~ "color: #c0ffee"
    refute body =~ ~r(\.exception-logo {\s*position: absolute)
  end

  test "custom banners can be rendered" do
    conn = put_req_header(conn(:get, "/boom"), "accept", "text/html")
    assert_raise RuntimeError, fn -> StyledRouter.call(conn, []) end

    {_status, _headers, body} = sent_resp(conn)
    assert body =~ "<h1>500, :error, %RuntimeError{message: \"oops\"}</h1>"
  end

  test "if the Accept header is something else than text/html, Markdown is rendered" do
    conn =
      conn(:get, "/")
      |> put_req_header("accept", "application/json")
      |> put_resp_header("content-security-policy", "abcdef")

    conn =
      render(conn, [], fn ->
        raise Plug.Parsers.UnsupportedMediaTypeError, media_type: "foo/bar"
      end)

    assert get_resp_header(conn, "content-type") == ["text/markdown; charset=utf-8"]

    assert get_resp_header(conn, "content-security-policy") == ["abcdef"]

    assert conn.resp_body =~ "# Plug.Parsers.UnsupportedMediaTypeError at GET /"
    assert conn.resp_body =~ "unsupported media type foo/bar"
  end

  test "render actions when an implementation of `Plug.Exception` has it" do
    [%{label: action_label}] = Plug.Exception.actions(%ActionableError{})

    conn =
      conn(:get, "/actionable_exception")
      |> put_req_header("accept", "text/html")
      |> Map.put(:secret_key_base, "secret")

    capture_log(fn -> assert_raise(ActionableError, fn -> Router.call(conn, []) end) end)

    {_status, _headers, body} = sent_resp(conn)
    assert body =~ ~s|action="/__plug__/debugger/action" method="POST"|
    assert body =~ action_label
  end

  test "does not render actions when the exception don't implement `Plug.Exception`" do
    conn =
      conn(:get, "/soft_boom")
      |> put_req_header("accept", "text/html")
      |> Map.put(:secret_key_base, "secret")

    capture_log(fn -> assert_raise(Exception, fn -> Router.call(conn, []) end) end)
    {_status, _headers, body} = sent_resp(conn)

    refute body =~ ~s|<form action="/__plug__/debugger/action" method="POST">|
  end

  test "does not render actions when no secret_key_base is present" do
    conn = put_req_header(conn(:get, "/actionable_exception"), "accept", "text/html")

    capture_log(fn ->
      assert_raise(ActionableError, fn ->
        Router.call(conn, [])
      end)
    end)

    {_status, _headers, body} = sent_resp(conn)

    refute body =~ ~s|<form action="/__plug__/debugger/action" method="POST">|
  end

  test "only render actions if request is html" do
    conn =
      conn(:get, "/actionable_exception")
      |> Map.put(:secret_key_base, "secret")

    capture_log(fn ->
      assert_raise(ActionableError, fn ->
        Router.call(conn, [])
      end)
    end)

    {_status, _headers, body} = sent_resp(conn)

    refute body =~ ~s|<form action="/__plug__/debugger/action" method="POST">|
  end

  test "sets last path as the current request path when is a GET" do
    path = "/actionable_exception"

    conn =
      conn(:get, path)
      |> put_req_header("accept", "text/html")
      |> Map.put(:secret_key_base, "secret")

    %Plug.Conn{resp_body: body} = render(conn, [], fn -> raise ActionableError end)
    assert body =~ ~s|<input type="hidden" name="last_path" value="#{path}">|
  end

  test "sets last path as the referer header when request is not a GET" do
    path = "/actionable_exception"
    referer = "/referer"

    conn =
      conn(:post, path)
      |> put_req_header("accept", "text/html")
      |> put_req_header("referer", referer)
      |> Map.put(:secret_key_base, "secret")

    %Plug.Conn{resp_body: body} = render(conn, [], fn -> raise ActionableError end)
    assert body =~ ~s|<input type="hidden" name="last_path" value="#{referer}">|
  end

  test "sets last path as / when request is not a GET and tehre is no referer" do
    conn =
      conn(:post, "/actionable_exception")
      |> put_req_header("accept", "text/html")
      |> Map.put(:secret_key_base, "secret")

    %Plug.Conn{resp_body: body} = render(conn, [], fn -> raise ActionableError end)
    assert body =~ ~s|<input type="hidden" name="last_path" value="/">|
  end

  test "executes an action" do
    secret_key_base = "secret"

    [%{encoded_handler: encoded_handler}] =
      Plug.Debugger.encoded_actions_for_exception(
        %ActionableError{},
        %Plug.Conn{secret_key_base: secret_key_base}
      )

    conn =
      conn(:post, "/__plug__/debugger/action", %{"encoded_handler" => encoded_handler})
      |> Map.put(:secret_key_base, secret_key_base)

    Router.call(conn, [])

    assert_received :actionable_error
  end

  test "does not execute an action that was tampered" do
    secret_key_base = "test"

    invalid_encoded_handler =
      Plug.Crypto.sign(
        "invalid",
        "plug-debugger-actions",
        {Process, :send, [self(), :tampered, []]}
      )

    conn =
      conn(:post, "/__plug__/debugger/action", %{"encoded_handler" => invalid_encoded_handler})
      |> Map.put(:secret_key_base, secret_key_base)

    capture_log(fn ->
      assert_raise(RuntimeError, fn ->
        Router.call(conn, [])
      end)
    end)

    refute_received :tampered
  end

  test "stacktrace from otp_app" do
    conn = stack([{Plug.Conn, :unknown, 1, file: "lib/plug/conn.ex", line: 1}])
    assert conn.resp_body =~ "Plug.Conn.unknown/1"
    assert conn.resp_body =~ ~r(<span class=\"filename\">\s*lib/plug/conn.ex)
    assert conn.resp_body =~ "<span class=\"line\">:1</span>"
    assert conn.resp_body =~ "<span class=\"app\">plug</span>"
    assert conn.resp_body =~ "<span class=\"ln\">1</span>"
    assert conn.resp_body =~ "<span class=\"code\">defmodule Plug.Conn do</span>"
  end

  test "stacktrace from elixir" do
    conn = stack([{GenServer, :call, 2, file: "lib/gen_server.ex", line: 10_000}])
    assert conn.resp_body =~ "<span class=\"info\">GenServer.call/2</span>"
    assert conn.resp_body =~ "<span class=\"line\">:10000</span>"
    assert conn.resp_body =~ "lib/gen_server.ex"
  end

  test "stacktrace from test" do
    conn =
      stack([
        {__MODULE__, :unknown, 1, file: Path.relative_to_cwd(__ENV__.file), line: __ENV__.line}
      ])

    assert conn.resp_body =~ "<span class=\"info\">Plug.DebuggerTest.unknown/1</span>"
    assert conn.resp_body =~ ~r(<span class=\"filename\">\s*test/plug/debugger_test.exs)
    assert conn.resp_body =~ "Path.relative_to_cwd(__ENV__.file)"
    refute conn.resp_body =~ "<span class=\"app\">plug</span>"
  end

  # This should always be the last test as we are checking for end of line.
  test "stacktrace at the end of file" do
    conn =
      stack([
        {__MODULE__, :unknown, 1, file: Path.relative_to_cwd(__ENV__.file), line: __ENV__.line}
      ])

    assert conn.resp_body =~ "<span class=\"code\">  end</span>"
  end
end
