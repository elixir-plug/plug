defmodule Plug.Adapters.Test.ConnTest do
  use ExUnit.Case, async: true

  import Plug.Test

  test "read_req_body/2" do
    conn = conn(:get, "/", "abcdefghij", headers: [{"content-type", "text/plain"}])
    {adapter, state} = conn.adapter

    assert {:more, "abcde", state} = adapter.read_req_body(state, length: 5)
    assert {:more, "f", state} = adapter.read_req_body(state, length: 1)
    assert {:more, "gh", state} = adapter.read_req_body(state, length: 2)
    assert {:ok, "ij", state} = adapter.read_req_body(state, length: 5)
    assert {:ok, "", _state} = adapter.read_req_body(state, length: 5)
  end

  test "no body or params" do
    conn = conn(:get, "/")
    {adapter, state} = conn.adapter
    assert conn.req_headers == []
    assert {:ok, "", _state} = adapter.read_req_body(state, length: 10)
  end

  test "custom body requires content-type" do
    assert_raise ArgumentError, fn ->
      conn(:get, "/", "abcdefgh")
    end
  end

  test "custom params sets content-type to multipart/mixed" do
    conn = conn(:get, "/", foo: "bar")
    assert conn.req_headers == [{"content-type", "multipart/mixed; charset: utf-8"}]
  end

  test "parse_req_multipart/4" do
    conn = conn(:get, "/", a: "b", c: [%{d: "e"}, "f"])
    {adapter, state} = conn.adapter
    assert {:ok, params, _} = adapter.parse_req_multipart(state, 1_000_000, fn _ -> end)
    assert params == %{"a" => "b", "c" => [%{"d" => "e"}, "f"]}
  end

  test "recycle/2" do
    conn = conn(:get, "/foo", a: "b", c: [%{d: "e"}, "f"], headers: [{"content-type", "text/plain"}])
           |> put_req_cookie("req_cookie", "req_cookie")
           |> put_req_cookie("del_cookie", "del_cookie")
           |> put_req_cookie("over_cookie", "pre_cookie")
           |> Plug.Conn.put_resp_cookie("over_cookie", "pos_cookie")
           |> Plug.Conn.put_resp_cookie("resp_cookie", "resp_cookie")
           |> Plug.Conn.delete_resp_cookie("del_cookie")

    conn = recycle(conn(:get, "/"), conn)
    assert conn.path_info == []

    conn = conn |> Plug.Conn.fetch_params |> Plug.Conn.fetch_cookies
    assert conn.params  == %{}
    assert conn.cookies == %{"req_cookie"  => "req_cookie",
                             "over_cookie" => "pos_cookie",
                             "resp_cookie" => "resp_cookie"}
  end
end
