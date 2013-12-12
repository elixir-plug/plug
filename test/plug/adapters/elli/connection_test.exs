defmodule Plug.Adapters.Elli.ConnectionTest do
  use ExUnit.Case, async: true

  alias  Plug.Conn
  import Plug.Connection

  ## Elli setup for testing

  setup_all do
    { :ok, _pid } = Plug.Adapters.Elli.http __MODULE__, [], port: 8003
    :ok
  end

  teardown_all do
    :ok = Plug.Adapters.Elli.shutdown(__MODULE__.HTTP)
  end

  def call(conn, []) do
    function = binary_to_atom Enum.first(conn.path_info) || "root"
    apply __MODULE__, function, [conn]
  rescue
    exception ->
      receive do
        { :plug_conn, :sent } ->
          :erlang.raise(:error, exception, :erlang.get_stacktrace)
      after
        0 ->
          { :halt, send(conn, 500, exception.message <> "\n" <>
                        Exception.format_stacktrace(System.stacktrace)) }
      end
  end

  ## Tests

  def root(Conn[] = conn) do
    assert conn.method == "HEAD"
    assert conn.path_info == []
    assert conn.query_string == "foo=bar&baz=bat"
    { :ok, conn }
  end

  def build(Conn[] = conn) do
    assert { Plug.Adapters.Elli.Connection, _ } = conn.adapter
    assert conn.path_info == ["build", "foo", "bar"]
    assert conn.query_string == ""
    assert conn.scheme == :http
    assert conn.host == "127.0.0.1"
    assert conn.port == 8003
    assert conn.method == "GET"
    { :ok, conn }
  end

  test "builds a connection" do
    assert { 204, _, _ } = request :head, "/?foo=bar&baz=bat"
    assert { 204, _, _ } = request :get, "/build/foo/bar"
    assert { 204, _, _ } = request :get, "//build//foo//bar"
  end

  def headers(conn) do
    assert conn.req_headers["foo"] == "bar"
    assert conn.req_headers["baz"] == "bat"
    { :ok, conn }
  end

  test "stores request headers" do
    assert { 204, _, _ } = request :get, "/headers", [{ "foo", "bar" }, { "baz", "bat" }]
  end

  def send_200(conn) do
    assert conn.state == :unset
    assert conn.resp_body == nil
    conn = send(conn, 200, "OK")
    assert conn.state == :sent
    assert conn.resp_body == nil
    { :ok, conn }
  end

  def send_500(conn) do
    { :ok, conn
           |> delete_resp_header("cache-control")
           |> put_resp_header("x-sample", "value")
           |> send(500, "ERROR") }
  end

  test "sends a response with status, headers and body" do
    assert { 200, headers, "OK" } = request :get, "/send_200"
    assert headers["cache-control"] == "max-age=0, private, must-revalidate"
    assert { 500, headers, "ERROR" } = request :get, "/send_500"
    assert headers["cache-control"] == nil
    assert headers["x-sample"] == "value"
  end

  test "skips body on head" do
    assert { 200, _, "" } = request :head, "/send_200"
  end

  def send_file(conn) do
    conn = send_file(conn, 200, __FILE__)
    assert conn.state == :sent
    assert conn.resp_body == nil
    { :ok, conn }
  end

  test "sends a file with status and headers" do
    assert { 200, headers, body } = request :get, "/send_file"
    assert body =~ "sends a file with status and headers"
    assert headers["cache-control"] == "max-age=0, private, must-revalidate"
    assert headers["content-length"] == File.stat!(__FILE__).size |> integer_to_binary
  end

  test "skips file on head" do
    assert { 200, _, "" } = request :head, "/send_file"
  end

  def send_chunked(conn) do
    conn = send_chunked(conn, 200)
    assert conn.state == :chunked
    { :ok, conn } = chunk(conn, "HELLO\n")
    { :ok, conn } = chunk(conn, "WORLD\n")
    { :ok, conn }
  end

  test "sends a chunked response with status and headers" do
    assert { 200, headers, "HELLO\nWORLD\n" } = request :get, "/send_chunked"
    assert headers["cache-control"] == "max-age=0, private, must-revalidate"
    assert headers["Transfer-Encoding"] == "chunked"
  end

  def stream_req_body(conn) do
    { adapter, state } = conn.adapter
    expected = :binary.copy("abcdefghij", 100_000)
    assert { ^expected, state } = read_req_body({ :ok, "", state }, "", adapter)
    assert { :done, state } = adapter.stream_req_body(state, 100_000)
    { :ok, conn.adapter({ adapter, state }) }
  end

  defp read_req_body({ :ok, buffer, state }, acc, adapter) do
    read_req_body(adapter.stream_req_body(state, 100_000), acc <> buffer, adapter)
  end

  defp read_req_body({ :done, state }, acc, _adapter) do
    { acc, state }
  end

  test "reads body" do
    body = :binary.copy("abcdefghij", 100_000)
    assert { 204, _, "" } = request :get, "/stream_req_body", [], body
    assert { 204, _, "" } = request :post, "/stream_req_body", [], body
  end

  ## Helpers

  defp request(verb, path, headers // [], body // "") do
    { :ok, status, headers, client } =
      :hackney.request(verb, "http://127.0.0.1:8003" <> path, headers, body, [])
    { :ok, body, _ } = :hackney.body(client)
    :hackney.close(client)
    { status, headers, body }
  end
end
