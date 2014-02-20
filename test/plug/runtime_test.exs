defmodule Plug.RuntimeTest do
  use ExUnit.Case, async: true
  use Plug.Test

  import Plug.Connection

  test "sets x-runtime header if none is set" do
    conn = wrap(conn(:get, "/"))
    assert Regex.match?(~r/^\d+(\.\d)?\d*$/, conn.resp_headers["x-runtime"])
  end

  test "doesn't set the x-runtime if it is already set" do
    fun = fn conn ->
      conn
      |> put_resp_header("x-runtime", "foo")
      |> send_resp(200, "Hello, world")
    end
    conn = wrap(conn(:get, "/"), Plug.Runtime.init([]), fun)
    assert conn.resp_headers["x-runtime"] == "foo"
  end

  test "allow a suffix to be set" do
    runtime = Plug.Runtime.init(name: "app")
    conn = wrap(conn(:get, "/"), runtime)
    assert Regex.match?(~r/^\d+(\.\d)?\d*$/, conn.resp_headers["x-runtime-app"])
  end

  @runtime Plug.Runtime.init([])

  defp wrap(conn, opts \\ @runtime, fun \\ hello_fun) do
    Plug.Runtime.wrap(conn, opts, fun)
  end

  defp hello_fun do
    fn conn -> send_resp(conn, 200, "Hello, world") end
  end
end
