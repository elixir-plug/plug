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
send          { :halt, send(conn, 500, exception.message <> "\n" <>
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

    assert { 200, _headers, "OK" } = conn.resp_body
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
    assert { 200, _headers, { :file, __FILE__ } } = conn.resp_body
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
    spawn(fn() -> __MODULE__.chunk_loop(conn) end)
    { :ok, conn }
  end

  # Send 10 separate chunks to the client.

  def chunk_loop(conn), do: chunk_loop(conn, 10)

  def chunk_loop(conn, 0), do: chunk(conn, "")
  def chunk_loop(conn, n) do
    :timer.sleep(100)
    case chunk(conn, to_string(n)) do
      { :ok, conn } ->
        chunk_loop(conn, n - 1)
      { :error, reason } ->
        IO.puts("error in sending chunk: #{inspect reason}")
    end
  end

  test "sends a chunked response with status and headers" do
    assert { 200, headers, "10987654321" } = request :get, "/send_chunked"
    assert headers["cache-control"] == "max-age=0, private, must-revalidate"
    assert headers["Transfer-Encoding"] == "chunked"
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
