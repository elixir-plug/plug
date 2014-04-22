defmodule Plug.HeadTest do
  use ExUnit.Case, async: true
  use Plug.Test

  @opts Plug.Head.init([])

  test "converts HEAD requests to GET" do
    conn = Plug.Head.call(conn(:head, "/"), @opts)
    assert conn.method == "GET"
  end

  test "HEAD responses have headers but do not have a body" do
    conn = conn(:head, "/")
           |> Plug.Head.call(@opts)
           |> put_resp_content_type("text/plain")
           |> send_resp(200, "Hello world")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    assert conn.resp_body == ""
  end
end
