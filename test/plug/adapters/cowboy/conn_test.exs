defmodule Plug.Adapters.Cowboy.ConnTest do
  use ExUnit.Case, async: true

  alias  Plug.Conn
  import Plug.Conn

  ## Cowboy setup for testing

  setup_all do
    {:ok, _pid} = Plug.Adapters.Cowboy.http __MODULE__, [], port: 8001
    :ok
  end

  teardown_all do
    :ok = Plug.Adapters.Cowboy.shutdown(__MODULE__.HTTP)
  end

  def init(opts) do
    opts
  end

  def call(conn, []) do
    function = binary_to_atom List.first(conn.path_info) || "root"
    apply __MODULE__, function, [conn]
  rescue
    exception ->
      receive do
        {:plug_conn, :sent} ->
          :erlang.raise(:error, exception, :erlang.get_stacktrace)
      after
        0 ->
          send_resp(conn, 500, exception.message <> "\n" <>
                    Exception.format_stacktrace(System.stacktrace))
      end
  end

  ## Tests

  def root(%Conn{} = conn) do
    assert conn.method == "HEAD"
    assert conn.path_info == []
    assert conn.query_string == "foo=bar&baz=bat"
    conn
  end

  def build(%Conn{} = conn) do
    assert {Plug.Adapters.Cowboy.Conn, _} = conn.adapter
    assert conn.path_info == ["build", "foo", "bar"]
    assert conn.query_string == ""
    assert conn.scheme == :http
    assert conn.host == "127.0.0.1"
    assert conn.port == 8001
    assert conn.method == "GET"
    conn
  end

  test "builds a connection" do
    assert {204, _, _} = request :head, "/?foo=bar&baz=bat"
    assert {204, _, _} = request :get, "/build/foo/bar"
    assert {204, _, _} = request :get, "//build//foo//bar"
  end

  def headers(conn) do
    assert get_req_header(conn, "foo") == ["bar"]
    assert get_req_header(conn, "baz") == ["bat"]
    conn
  end

  test "stores request headers" do
    assert {204, _, _} = request :get, "/headers", [{"foo", "bar"}, {"baz", "bat"}]
  end

  def send_200(conn) do
    assert conn.state == :unset
    assert conn.resp_body == nil
    conn = send_resp(conn, 200, "OK")
    assert conn.state == :sent
    assert conn.resp_body == nil
    conn
  end

  def send_500(conn) do
    conn
    |> delete_resp_header("cache-control")
    |> put_resp_header("x-sample", "value")
    |> send_resp(500, ["ERR", ["OR"]])
  end

  test "sends a response with status, headers and body" do
    assert {200, headers, "OK"} = request :get, "/send_200"
    assert List.keyfind(headers, "cache-control", 0) ==
           {"cache-control", "max-age=0, private, must-revalidate"}
    assert {500, headers, "ERROR"} = request :get, "/send_500"
    assert List.keyfind(headers, "cache-control", 0) == nil
    assert List.keyfind(headers, "x-sample", 0) ==
           {"x-sample", "value"}
  end

  test "skips body on head" do
    assert {200, _, ""} = request :head, "/send_200"
  end

  def send_file(conn) do
    conn = send_file(conn, 200, __ENV__.file)
    assert conn.state == :sent
    assert conn.resp_body == nil
    conn
  end

  test "sends a file with status and headers" do
    assert {200, headers, body} = request :get, "/send_file"
    assert body =~ "sends a file with status and headers"
    assert List.keyfind(headers, "cache-control", 0) ==
           {"cache-control", "max-age=0, private, must-revalidate"}
    assert List.keyfind(headers, "content-length", 0) ==
           {"content-length", File.stat!(__ENV__.file).size |> integer_to_binary}
  end

  test "skips file on head" do
    assert {200, _, ""} = request :head, "/send_file"
  end

  def send_chunked(conn) do
    conn = send_chunked(conn, 200)
    assert conn.state == :chunked
    {:ok, conn} = chunk(conn, "HELLO\n")
    {:ok, conn} = chunk(conn, ["WORLD", ["\n"]])
    conn
  end

  test "sends a chunked response with status and headers" do
    assert {200, headers, "HELLO\nWORLD\n"} = request :get, "/send_chunked"
    assert List.keyfind(headers, "cache-control", 0) ==
           {"cache-control", "max-age=0, private, must-revalidate"}
    assert List.keyfind(headers, "transfer-encoding", 0) ==
           {"transfer-encoding", "chunked"}
  end

  def stream_req_body(conn) do
    {adapter, state} = conn.adapter
    expected = :binary.copy("abcdefghij", 100_000)
    assert {^expected, state} = read_req_body({:ok, "", state}, "", adapter)
    assert {:done, state} = adapter.stream_req_body(state, 100_000)
    %{conn | adapter: {adapter, state}}
  end

  defp read_req_body({:ok, buffer, state}, acc, adapter) do
    read_req_body(adapter.stream_req_body(state, 100_000), acc <> buffer, adapter)
  end

  defp read_req_body({:done, state}, acc, _adapter) do
    {acc, state}
  end

  test "reads body" do
    body = :binary.copy("abcdefghij", 100_000)
    assert {204, _, ""} = request :get, "/stream_req_body", [], body
    assert {204, _, ""} = request :post, "/stream_req_body", [], body
  end

  def multipart(conn) do
    conn = Plug.Parsers.call(conn, parsers: [Plug.Parsers.MULTIPART], limit: 8_000_000)
    assert conn.params["name"] == "hello"

    assert %Plug.Upload{} = file = conn.params["pic"]
    assert File.read!(file.path) == "hello\n\n"
    assert file.content_type == "text/plain"
    assert file.filename == "foo.txt"

    conn
  end

  test "parses multipart requests" do
    multipart = "------WebKitFormBoundaryw58EW1cEpjzydSCq\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\nhello\r\n------WebKitFormBoundaryw58EW1cEpjzydSCq\r\nContent-Disposition: form-data; name=\"pic\"; filename=\"foo.txt\"\r\nContent-Type: text/plain\r\n\r\nhello\n\n\r\n------WebKitFormBoundaryw58EW1cEpjzydSCq\r\nContent-Disposition: form-data; name=\"commit\"\r\n\r\nCreate User\r\n------WebKitFormBoundaryw58EW1cEpjzydSCq--\r\n"
    headers =
      [{"Content-Type", "multipart/form-data; boundary=----WebKitFormBoundaryw58EW1cEpjzydSCq"},
       {"Content-Length", size(multipart)}]

    assert {204, _, _} = request :get, "/multipart", headers, multipart
    assert {204, _, _} = request :get, "/multipart?name=overriden", headers, multipart
  end

  def https(conn) do
    assert conn.scheme == :https
    send_resp(conn, 200, "OK")
  end

  @https_options [
    port: 8002, password: "cowboy",
    keyfile: Path.expand("../../../fixtures/ssl/key.pem", __DIR__),
    certfile: Path.expand("../../../fixtures/ssl/cert.pem", __DIR__)
  ]

  test "https" do
    {:ok, _pid} = Plug.Adapters.Cowboy.https __MODULE__, [], @https_options
    assert {:ok, 200, _headers, client} = :hackney.get("https://127.0.0.1:8002/https", [], "", [])
    assert {:ok, "OK", _client} = :hackney.body(client)
    :hackney.close(client)
  after
    :ok = Plug.Adapters.Cowboy.shutdown __MODULE__.HTTPS
  end

  ## Helpers

  defp request(verb, path, headers \\ [], body \\ "") do
    {:ok, status, headers, client} =
      :hackney.request(verb, "http://127.0.0.1:8001" <> path, headers, body, [])
    {:ok, body, _} = :hackney.body(client)
    :hackney.close(client)
    {status, headers, body}
  end
end
