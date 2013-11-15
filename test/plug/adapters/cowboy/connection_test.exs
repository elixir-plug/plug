defmodule Plug.Adapters.Cowboy.ConnectionTest do
  use ExUnit.Case, async: true

  ## Cowboy setup for testing

  setup_all do
    dispatch = [{ :_, [ {:_, Plug.Adapters.Cowboy.Handler, __MODULE__ } ] }]
    env = [dispatch: :cowboy_router.compile(dispatch)]
    { :ok, _pid } = :cowboy.start_http(__MODULE__, 100, [port: 8001], [env: env])
    :ok
  end

  teardown_all do
    :ok = :cowboy.stop_listener(__MODULE__)
    :ok
  end

  def plug(conn, []) do
    function = binary_to_atom Enum.first(conn.path_info) || "root"
    apply __MODULE__, function, [conn]
  # rescue
  #   exception ->
  #     conn.send(500, exception.message <> "\n" <> Exception.format_stacktrace)
  end

  ## Tests

  def root(Plug.Conn[] = conn) do
    assert conn.path_info == []
    assert conn.script_name == []
    conn
  end

  def build(Plug.Conn[] = conn) do
    assert { Plug.Adapters.Cowboy.Connection, _ } = conn.adapter
    assert conn.path_info == ["build", "foo", "bar"]
    assert conn.script_name == []
    conn
  end

  test "builds a connection" do
    assert_ok request :get, "/"
    assert_ok request :get, "/build/foo/bar"
    assert_ok request :get, "//build//foo//bar"
  end

  ## Helpers

  defp assert_ok({ 204, _, _ }), do: :ok
  defp assert_ok({ status, _, body }) do
    flunk "Expected ok response, got status #{inspect status} with body #{inspect body}"
  end

  defp request(verb, path, headers // [], body // "") do
    { :ok, status, headers, client } =
      :hackney.request(verb, "http://127.0.0.1:8001" <> path, headers, body, [])
    { :ok, body, _ } = :hackney.body(client)
    { status, headers, body }
  end
end
