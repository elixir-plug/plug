defmodule Plug.MethodOverrideTest do
  use ExUnit.Case, async: true
  use Plug.Test

  test "converts POST to DELETE when X-HTTP-Method-Override: DELETE header is specified" do
    headers = [{"x-http-method-override", "DELETE"}, {"content-type", "application/x-www-form-urlencoded"}]
    conn = call(conn(:post, "/", "", headers: headers))
    assert conn.method == "DELETE"
  end

  test "converts POST to DELETE when _method=DELETE param is specified" do
    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    conn = call(conn(:post, "/", "_method=DELETE", headers: headers))
    assert conn.method == "DELETE"
  end

  test "converts POST to PUT when X-HTTP-Method-Override: PUT header is specified" do
    headers = [{"x-http-method-override", "PUT"}, {"content-type", "application/x-www-form-urlencoded"}]
    conn = call(conn(:post, "/", "", headers: headers))
    assert conn.method == "PUT"
  end

  test "converts POST to PUT when _method=PUT param is specified" do
    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    conn = call(conn(:post, "/", "_method=PUT", headers: headers))
    assert conn.method == "PUT"
  end

  test "converts POST to PATCH when X-HTTP-Method-Override: PATCH header is specified" do
    headers = [{"x-http-method-override", "PATCH"}, {"content-type", "application/x-www-form-urlencoded"}]
    conn = call(conn(:post, "/", "", headers: headers))
    assert conn.method == "PATCH"
  end

  test "converts POST to PATCH when _method=PATCH param is specified" do
    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    conn = call(conn(:post, "/", "_method=PATCH", headers: headers))
    assert conn.method == "PATCH"
  end

  @parsers  Plug.Parsers.init(parsers: [Plug.Parsers.URLENCODED])
  @override Plug.MethodOverride.init([])

  defp call(conn) do
    conn
    |> Plug.Parsers.call(@parsers)
    |> Plug.MethodOverride.call(@override)
  end
end
