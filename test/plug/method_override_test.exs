defmodule Plug.MethodOverrideTest do
  use ExUnit.Case, async: true
  use Plug.Test

  def urlencoded_conn(method, body) do
    method
    |> conn("/?_method=DELETE", body)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
  end

  test "no-op when body is not parsed" do
    conn = call(conn(:post, "/"))
    assert conn.method == "POST"
  end

  test "ignores query parameters" do
    conn = call(urlencoded_conn(:post, ""))
    assert conn.method == "POST"
  end

  # This can happen with JSON bodies that have _method as something other than a string.
  test "ignores non-string _method in the body" do
    # We don't depend on any JSON library here, so we just shove the "parsed" JSON
    # in the :body_params directly.
    conn =
      conn(:post, "/", "")
      |> Map.put(:body_params, %{"_method" => ["put"]})
      |> Plug.run([{Plug.MethodOverride, []}])

    assert conn.method == "POST"
  end

  test "converts POST to DELETE when _method=DELETE param is specified" do
    conn = call(urlencoded_conn(:post, "_method=DELETE"))
    assert conn.method == "DELETE"
  end

  test "converts POST to PUT when _method=PUT param is specified" do
    conn = call(urlencoded_conn(:post, "_method=PUT"))
    assert conn.method == "PUT"
  end

  test "converts POST to PATCH when _method=PATCH param is specified" do
    conn = call(urlencoded_conn(:post, "_method=PATCH"))
    assert conn.method == "PATCH"
  end

  test "the _method parameter works with non-uppercase methods" do
    conn = call(urlencoded_conn(:post, "_method=delete"))
    assert conn.method == "DELETE"
  end

  test "non-POST requests are not modified" do
    conn = call(urlencoded_conn(:get, "_method=DELETE"))
    assert conn.method == "GET"

    conn = call(urlencoded_conn(:put, "_method=DELETE"))
    assert conn.method == "PUT"
  end

  @parsers Plug.Parsers.init(parsers: [Plug.Parsers.URLENCODED])
  @override Plug.MethodOverride.init([])

  defp call(conn) do
    conn
    |> Plug.Parsers.call(@parsers)
    |> Plug.MethodOverride.call(@override)
  end
end
