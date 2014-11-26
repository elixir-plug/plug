defmodule Plug.DebuggerTest do
  use ExUnit.Case, async: true
  use Plug.Test

  defmodule Router do
    use Plug.Router
    use Plug.Debugger, otp_app: :plug

    plug :match
    plug :dispatch

    get "/boom" do
      resp conn, 200, "oops"
      raise "oops"
    end

    get "/send_and_boom" do
      send_resp conn, 200, "oops"
      raise "oops"
    end
  end

  test "call/2 is overridden" do
    assert_raise RuntimeError, "oops", fn ->
      conn(:get, "/boom") |> Router.call([])
    end

    assert_received {:plug_conn, :sent}
  end

  test "call/2 is overridden but is a no-op when response is already sent" do
    assert_raise RuntimeError, "oops", fn ->
      conn(:get, "/send_and_boom") |> Router.call([])
    end

    assert_received {:plug_conn, :sent}
  end

  defp render(conn, opts, fun) do
    opts =
      opts
      |> Keyword.put_new(:stack, [])
      |> Keyword.put_new(:otp_app, :plug)

    try do
      fun.()
    catch
      kind, error -> Plug.Debugger.render(conn, kind, error, opts[:stack], opts)
    else
      _ -> flunk "function should have failed"
    end
  end

  test "exception page for throws" do
    conn = render(conn(:get, "/"), [], fn ->
      throw :hello
    end)

    assert conn.status == 500
    assert conn.resp_body =~ "unhandled throw at GET /"
    assert conn.resp_body =~ ":hello"
  end

  test "exception page for exceptions" do
    conn = render(conn(:get, "/"), [], fn ->
      raise Plug.Parsers.UnsupportedMediaTypeError, media_type: "foo/bar"
    end)

    assert conn.status == 415
    assert conn.resp_body =~ "Plug.Parsers.UnsupportedMediaTypeError at GET /"
    assert conn.resp_body =~ "unsupported media type foo/bar"
  end

  test "exception page for exits" do
    conn = render(conn(:get, "/"), [], fn ->
      exit {:timedout, {GenServer, :call, [:foo, :bar]}}
    end)

    assert conn.status == 500
    assert conn.resp_body =~ "unhandled exit at GET /"
    assert conn.resp_body =~ "exited in: GenServer.call(:foo, :bar)"
  end

  defp stack(stack) do
    render(conn(:get, "/"), [stack: stack], fn ->
      raise "oops"
    end)
  end

  test "uses PLUG_EDITOR" do
    System.put_env("PLUG_EDITOR", "hello://open?file=__FILE__&line=__LINE__")

    conn = stack [{Plug.Conn, :unknown, 1, file: "lib/plug/conn.ex", line: 1}]
    file = Path.expand("lib/plug/conn.ex")
    assert conn.resp_body =~ "hello://open?file=#{file}&amp;line=1"

    conn = stack [{GenServer, :call, 2, file: "lib/gen_server.ex", line: 10000}]
    file = Path.expand(GenServer.__info__(:compile)[:source])
    assert conn.resp_body =~ "hello://open?file=#{file}&amp;line=10000"
  end

  test "stacktrace from otp_app" do
    conn = stack [{Plug.Conn, :unknown, 1, file: "lib/plug/conn.ex", line: 1}]
    assert conn.resp_body =~ "data-context=\"app\""
    assert conn.resp_body =~ "<strong>Plug.Conn.unknown/1</strong>"
    assert conn.resp_body =~ "<span class=\"filename\">lib/plug/conn.ex</span>"
    assert conn.resp_body =~ "(line <span class=\"line\">1</span>)"
    assert conn.resp_body =~ "<span class=\"app\">(plug)</span>"
    assert conn.resp_body =~ "<span class=\"ln\">1</span>"
    assert conn.resp_body =~ "<span>defmodule Plug.Conn do\n</span>"
  end

  test "stacktrace from elixir" do
    conn = stack [{GenServer, :call, 2, file: "lib/gen_server.ex", line: 10000}]
    assert conn.resp_body =~ "data-context=\"all\""
    assert conn.resp_body =~ "<strong>GenServer.call/2</strong>"
    assert conn.resp_body =~ "(line <span class=\"line\">10000</span>)"
    assert conn.resp_body =~ "<span class=\"filename\">lib/gen_server.ex</span>"
  end

  test "stacktrace from test" do
    conn = stack [{__MODULE__, :unknown, 1,
                   file: Path.relative_to_cwd(__ENV__.file), line: __ENV__.line}]

    assert conn.resp_body =~ "data-context=\"all\""
    assert conn.resp_body =~ "<strong>Plug.DebuggerTest.unknown/1</strong>"
    assert conn.resp_body =~ "<span class=\"filename\">test/plug/debugger_test.exs</span>"
    assert conn.resp_body =~ "Path.relative_to_cwd(__ENV__.file)"
    refute conn.resp_body =~ "<span class=\"app\">(plug)</span>"
  end

  # This should always be the last test as we are checing for end of line.

  test "stacktrace at the end of file" do
    conn = stack [{__MODULE__, :unknown, 1,
                   file: Path.relative_to_cwd(__ENV__.file), line: __ENV__.line}]
    assert conn.resp_body =~ "<span>end\n</span>"
  end
end
