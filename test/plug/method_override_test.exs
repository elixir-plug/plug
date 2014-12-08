defmodule Plug.MethodOverrideTest do
  use ExUnit.Case, async: true
  use Plug.Test

  @content_type_header {"content-type", "application/x-www-form-urlencoded"}

  test "converts POST to DELETE when X-HTTP-Method-Override: DELETE header is specified" do
    headers = [{"x-http-method-override", "DELETE"}, @content_type_header]
    conn = call(conn(:post, "/", "", headers: headers))
    assert conn.method == "DELETE"
  end

  test "converts POST to DELETE when _method=DELETE param is specified" do
    conn = call(conn(:post, "/", "_method=DELETE", headers: [@content_type_header]))
    assert conn.method == "DELETE"
  end

  test "converts POST to PUT when X-HTTP-Method-Override: PUT header is specified" do
    headers = [{"x-http-method-override", "PUT"}, @content_type_header]
    conn = call(conn(:post, "/", "", headers: headers))
    assert conn.method == "PUT"
  end

  test "converts POST to PUT when _method=PUT param is specified" do
    conn = call(conn(:post, "/", "_method=PUT", headers: [@content_type_header]))
    assert conn.method == "PUT"
  end

  test "converts POST to PATCH when X-HTTP-Method-Override: PATCH header is specified" do
    headers = [{"x-http-method-override", "PATCH"}, @content_type_header]
    conn = call(conn(:post, "/", "", headers: headers))
    assert conn.method == "PATCH"
  end

  test "converts POST to PATCH when _method=PATCH param is specified" do
    conn = call(conn(:post, "/", "_method=PATCH", headers: [@content_type_header]))
    assert conn.method == "PATCH"
  end

  test "the X-HTTP-Method-Override header works with non-uppercase methods" do
    headers = [{"x-http-method-override", "pUt"}, @content_type_header]
    conn = call(conn(:post, "/", "", headers: headers))
    assert conn.method == "PUT"
  end

  test "the _method parameter works with non-uppercase methods" do
    conn = call(conn(:post, "/", "_method=delete", headers: [@content_type_header]))
    assert conn.method == "DELETE"
  end

  @parsers  Plug.Parsers.init(parsers: [Plug.Parsers.URLENCODED])
  @override Plug.MethodOverride.init([])

  defp call(conn) do
    conn
    |> Plug.Parsers.call(@parsers)
    |> Plug.MethodOverride.call(@override)
  end
end
