defmodule Plug.HeadTest do

  defmodule HelloPlug do
    import Plug.Connection

    def call(conn, []) do
      conn = conn
             |> put_resp_content_type("text/plain")
             |> send_resp(200, "Hello world")
      { :ok, conn }
    end
  end

  use ExUnit.Case, async: true
  use Plug.Test

  test "converts HEAD requests to GET" do
    assert { :ok, conn } = Plug.Head.call(conn(:head, "/"), [])
    assert conn.method == "GET"
  end

  test "HEAD responses have headers but do not have a body" do
    conn = conn(:head, "/")
    { :ok, conn } = Plug.Head.call(conn, [])
    assert { :ok, conn } = HelloPlug.call(conn, [])
    assert conn.status == 200
    assert conn.resp_headers["content-type"] == "text/plain; charset=utf-8"
    assert conn.resp_body == ""
  end
end
