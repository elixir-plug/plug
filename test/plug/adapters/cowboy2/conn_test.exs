defmodule Plug.Adapters.Cowboy2.ConnTest do
  use ExUnit.Case, async: true

  alias Plug.Conn
  import Plug.Conn
  import ExUnit.CaptureLog

  @moduletag :cowboy2

  ## Cowboy2 setup for testing
  #
  # We use hackney to perform an HTTP request against the cowboy/plug running
  # on port 8003. Plug then uses Kernel.apply/3 to dispatch based on the first
  # element of the URI's path.
  #
  # e.g. `assert {204, _, _} = request :get, "/build/foo/bar"` will perform a
  # GET http://127.0.0.1:8003/build/foo/bar and Plug will call build/1.

  @https_options [
    port: 8004,
    password: "cowboy",
    keyfile: Path.expand("../../../fixtures/ssl/key.pem", __DIR__),
    certfile: Path.expand("../../../fixtures/ssl/cert.pem", __DIR__)
  ]

  setup_all do
    {:ok, _pid} = Plug.Adapters.Cowboy2.http(__MODULE__, [], port: 8003)
    {:ok, _pid} = Plug.Adapters.Cowboy2.https(__MODULE__, [], @https_options)

    on_exit(fn ->
      :ok = Plug.Adapters.Cowboy2.shutdown(__MODULE__.HTTP)
      :ok = Plug.Adapters.Cowboy2.shutdown(__MODULE__.HTTPS)
    end)

    :ok
  end

  @already_sent {:plug_conn, :sent}

  def init(opts) do
    opts
  end

  def call(conn, []) do
    # Assert we never have a lingering @already_sent entry in the inbox
    refute_received @already_sent

    function = String.to_atom(List.first(conn.path_info) || "root")
    apply(__MODULE__, function, [conn])
  rescue
    exception ->
      receive do
        {:plug_conn, :sent} ->
          :erlang.raise(:error, exception, :erlang.get_stacktrace())
      after
        0 ->
          send_resp(
            conn,
            500,
            Exception.message(exception) <>
              "\n" <> Exception.format_stacktrace(System.stacktrace())
          )
      end
  end

  ## Tests

  def root(%Conn{} = conn) do
    assert conn.method == "HEAD"
    assert conn.path_info == []
    assert conn.query_string == "foo=bar&baz=bat"
    assert conn.request_path == "/"
    resp(conn, 200, "ok")
  end

  def build(%Conn{} = conn) do
    assert {Plug.Adapters.Cowboy2.Conn, _} = conn.adapter
    assert conn.path_info == ["build", "foo", "bar"]
    assert conn.query_string == ""
    assert conn.scheme == :http
    assert conn.host == "127.0.0.1"
    assert conn.port == 8003
    assert conn.method == "GET"
    assert {{127, 0, 0, 1}, _} = conn.peer
    assert conn.remote_ip == {127, 0, 0, 1}
    resp(conn, 200, "ok")
  end

  test "builds a connection" do
    assert {200, _, _} = request(:head, "/?foo=bar&baz=bat")
    assert {200, _, _} = request(:get, "/build/foo/bar")
    assert {200, _, _} = request(:get, "//build//foo//bar")
  end

  def return_request_path(%Conn{} = conn) do
    resp(conn, 200, conn.request_path)
  end

  test "request_path" do
    assert {200, _, "/return_request_path/foo"} = request(:get, "/return_request_path/foo?barbat")

    assert {200, _, "/return_request_path/foo/bar"} =
             request(:get, "/return_request_path/foo/bar?bar=bat")

    assert {200, _, "/return_request_path/foo/bar/"} =
             request(:get, "/return_request_path/foo/bar/?bar=bat")

    assert {200, _, "/return_request_path/foo//bar"} =
             request(:get, "/return_request_path/foo//bar")

    assert {200, _, "//return_request_path//foo//bar//"} =
             request(:get, "//return_request_path//foo//bar//")
  end

  def headers(conn) do
    assert get_req_header(conn, "foo") == ["bar"]
    assert get_req_header(conn, "baz") == ["bat"]
    resp(conn, 200, "ok")
  end

  test "stores request headers" do
    assert {200, _, _} = request(:get, "/headers", [{"foo", "bar"}, {"baz", "bat"}])
  end

  test "fails on large headers" do
    assert capture_log(fn ->
             cookie = "bar=" <> String.duplicate("a", 8_000_000)
             response = request(:get, "/headers", [{"cookie", cookie}])
             assert match?({431, _, _}, response) or match?({:error, :closed}, response)
             assert {200, _, _} = request(:get, "/headers", [{"foo", "bar"}, {"baz", "bat"}])
           end) =~ "Cowboy returned 431 and there are no headers in the connection"
  end

  def send_200(conn) do
    assert conn.state == :unset
    assert conn.resp_body == nil
    conn = send_resp(conn, 200, "OK")
    assert conn.state == :sent
    assert conn.resp_body == nil
    conn
  end

  def send_418(conn) do
    send_resp(conn, 418, "")
  end

  def send_451(conn) do
    send_resp(conn, 451, "")
  end

  def send_500(conn) do
    conn
    |> delete_resp_header("cache-control")
    |> put_resp_header("x-sample", "value")
    |> send_resp(500, ["ERR", ["OR"]])
  end

  test "sends a response with status, headers and body" do
    assert {200, headers, "OK"} = request(:get, "/send_200")

    assert List.keyfind(headers, "cache-control", 0) ==
             {"cache-control", "max-age=0, private, must-revalidate"}

    assert {500, headers, "ERROR"} = request(:get, "/send_500")
    assert List.keyfind(headers, "cache-control", 0) == nil
    assert List.keyfind(headers, "x-sample", 0) == {"x-sample", "value"}
  end

  test "allows customized statuses based on config" do
    assert {451, _headers, ""} = request(:get, "/send_451")
    {:ok, ref} = :hackney.get("http://127.0.0.1:8003/send_451", [], "", async: :once)
    assert_receive({:hackney_response, ^ref, {:status, 451, "Unavailable For Legal Reasons"}})
    :hackney.close(ref)
  end

  test "existing statuses can be customized" do
    assert {418, _headers, ""} = request(:get, "/send_418")
    {:ok, ref} = :hackney.get("http://127.0.0.1:8003/send_418", [], "", async: :once)
    assert_receive({:hackney_response, ^ref, {:status, 418, "Totally not a teapot"}})
    :hackney.close(ref)
  end

  test "skips body on head" do
    assert {200, _, nil} = request(:head, "/send_200")
  end

  def send_file(conn) do
    conn = send_file(conn, 200, __ENV__.file)
    assert conn.state == :file
    assert conn.resp_body == nil
    conn
  end

  test "sends a file with status and headers" do
    assert {200, headers, body} = request(:get, "/send_file")
    assert body =~ "sends a file with status and headers"

    assert List.keyfind(headers, "cache-control", 0) ==
             {"cache-control", "max-age=0, private, must-revalidate"}

    assert List.keyfind(headers, "content-length", 0) ==
             {
               "content-length",
               __ENV__.file |> File.stat!() |> Map.fetch!(:size) |> Integer.to_string()
             }
  end

  test "skips file on head" do
    assert {200, _, nil} = request(:head, "/send_file")
  end

  def send_chunked(conn) do
    conn = send_chunked(conn, 200)
    assert conn.state == :chunked
    {:ok, conn} = chunk(conn, "HELLO\n")
    {:ok, conn} = chunk(conn, ["WORLD", ["\n"]])
    conn
  end

  test "sends a chunked response with status and headers" do
    assert {200, headers, "HELLO\nWORLD\n"} = request(:get, "/send_chunked")

    assert List.keyfind(headers, "cache-control", 0) ==
             {"cache-control", "max-age=0, private, must-revalidate"}

    assert List.keyfind(headers, "transfer-encoding", 0) == {"transfer-encoding", "chunked"}
  end

  def read_req_body(conn) do
    expected = :binary.copy("abcdefghij", 100_000)
    assert {:ok, ^expected, conn} = read_body(conn)
    assert {:ok, "", conn} = read_body(conn)
    resp(conn, 200, "ok")
  end

  def read_req_body_partial(conn) do
    assert {:more, _body, conn} = read_body(conn, length: 5, read_length: 5)
    resp(conn, 200, "ok")
  end

  test "reads body" do
    body = :binary.copy("abcdefghij", 100_000)
    assert {200, _, "ok"} = request(:post, "/read_req_body_partial", [], body)
    assert {200, _, "ok"} = request(:get, "/read_req_body", [], body)
    assert {200, _, "ok"} = request(:post, "/read_req_body", [], body)
  end

  def multipart(conn) do
    conn = Plug.Parsers.call(conn, parsers: [Plug.Parsers.MULTIPART], length: 8_000_000)
    assert conn.params["name"] == "hello"
    assert conn.params["status"] == ["choice1", "choice2"]
    assert conn.params["empty"] == nil

    assert %Plug.Upload{} = file = conn.params["pic"]
    assert File.read!(file.path) == "hello\n\n"
    assert file.content_type == "text/plain"
    assert file.filename == "foo.txt"

    resp(conn, 200, "ok")
  end

  test "parses multipart requests" do
    multipart = """
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"name\"\r
    \r
    hello\r
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"pic\"; filename=\"foo.txt\"\r
    Content-Type: text/plain\r
    \r
    hello

    \r
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"empty\"; filename=\"\"\r
    Content-Type: application/octet-stream\r
    \r
    \r
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name="status[]"\r
    \r
    choice1\r
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name="status[]"\r
    \r
    choice2\r
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"commit\"\r
    \r
    Create User\r
    ------w58EW1cEpjzydSCq--\r
    """

    headers =
      [
        {"Content-Type", "multipart/form-data; boundary=----w58EW1cEpjzydSCq"},
        {"Content-Length", byte_size(multipart)}
      ]

    assert {200, _, _} = request(:post, "/multipart", headers, multipart)
    assert {200, _, _} = request(:post, "/multipart?name=overriden", headers, multipart)
  end

  def file_too_big(conn) do
    conn = Plug.Parsers.call(conn, parsers: [Plug.Parsers.MULTIPART], length: 5)

    assert %Plug.Upload{} = file = conn.params["pic"]
    assert File.read!(file.path) == "hello\n\n"
    assert file.content_type == "text/plain"
    assert file.filename == "foo.txt"

    resp(conn, 200, "ok")
  end

  test "returns parse error when file pushed the boundaries in multipart requests" do
    multipart = """
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"pic\"; filename=\"foo.txt\"\r
    Content-Type: text/plain\r
    \r
    hello

    \r
    ------w58EW1cEpjzydSCq--\r
    """

    headers =
      [
        {"Content-Type", "multipart/form-data; boundary=----w58EW1cEpjzydSCq"},
        {"Content-Length", byte_size(multipart)}
      ]

    assert {500, _, body} = request(:post, "/file_too_big", headers, multipart)
    assert body =~ "the request is too large"
  end

  test "validates utf-8 on multipart requests" do
    multipart = """
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"name\"\r
    \r
    #{<<139>>}\r
    ------w58EW1cEpjzydSCq\r
    """

    headers =
      [
        {"Content-Type", "multipart/form-data; boundary=----w58EW1cEpjzydSCq"},
        {"Content-Length", byte_size(multipart)}
      ]

    assert {500, _, body} = request(:post, "/multipart", headers, multipart)
    assert body =~ "invalid UTF-8 on multipart body, got byte 139"
  end

  test "returns parse error when body is badly formatted in multipart requests" do
    multipart = """
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"name\"\r
    ------w58EW1cEpjzydSCq\r
    """

    headers =
      [
        {"Content-Type", "multipart/form-data; boundary=----w58EW1cEpjzydSCq"},
        {"Content-Length", byte_size(multipart)}
      ]

    assert {500, _, body} = request(:post, "/multipart", headers, multipart)

    assert body =~
             "malformed request, a RuntimeError exception was raised with message \"invalid multipart"

    multipart = """
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"name\"\r
    \r
    hello
    """

    headers =
      [
        {"Content-Type", "multipart/form-data; boundary=----w58EW1cEpjzydSCq"},
        {"Content-Length", byte_size(multipart)}
      ]

    assert {500, _, body} = request(:post, "/multipart", headers, multipart)

    assert body =~
             "malformed request, a RuntimeError exception was raised with message \"invalid multipart"
  end

  def https(conn) do
    assert conn.scheme == :https
    send_resp(conn, 200, "OK")
  end

  test "https" do
    ssl_options = [
      ssl_options: [cacertfile: @https_options[:certfile], server_name_indication: 'localhost']
    ]

    assert {:ok, 200, _headers, client} =
             :hackney.get("https://127.0.0.1:8004/https", [], "", ssl_options)

    assert {:ok, "OK"} = :hackney.body(client)
    :hackney.close(client)
  end

  def http2(conn) do
    %{adapter: {Plug.Adapters.Cowboy2.Conn, %{version: version}}} = conn
    send_resp(conn, 200, Atom.to_string(version))
  end

  test "http2" do
    opts = [
      cacertfile: @https_options[:certfile], server_name_indication: 'localhost', port: 8004
    ]

    {:ok, _} = Application.ensure_all_started(:kadabra)
    {:ok, pid} = Kadabra.open('localhost', :https, opts)
    Kadabra.get(pid, "/http2")

    assert_receive({:end_stream, %Kadabra.Stream.Response{body: "HTTP/2", status: 200}}, 1_000)
  end

  ## Helpers

  defp request(:head = verb, path) do
    {:ok, status, headers} = :hackney.request(verb, "http://127.0.0.1:8003" <> path, [], "", [])
    {status, headers, nil}
  end

  defp request(verb, path, headers \\ [], body \\ "") do
    case :hackney.request(verb, "http://127.0.0.1:8003" <> path, headers, body, []) do
      {:ok, status, headers, client} ->
        {:ok, body} = :hackney.body(client)
        :hackney.close(client)
        {status, headers, body}

      {:error, _} = error ->
        error
    end
  end
end
