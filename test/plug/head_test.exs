defmodule Plug.HeadTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  @opts Plug.Head.init([])

  test "converts HEAD requests to GET requests" do
    conn = Plug.Head.call(conn(:head, "/"), @opts)
    assert conn.method == "GET"
  end

  test "HEAD responses have headers but do not have a body" do
    conn =
      conn(:head, "/")
      |> Plug.Head.call(@opts)
      |> put_resp_content_type("text/plain")
      |> send_resp(200, "Hello world")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    assert conn.resp_body == ""
  end

  test "if the request is different from HEAD, conn must be returned as is" do
    conn =
      conn(:get, "/")
      |> Plug.Head.call(@opts)
      |> send_resp(200, "Hello world")

    assert conn.status == 200
    assert conn.method == "GET"
    assert conn.resp_body == "Hello world"
  end
end
