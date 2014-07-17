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

  test "recycle/1" do
    conn = conn(:get, "/", a: "b", c: [%{d: "e"}, "f"], headers: [{"content-type", "text/plain"}])
           |> put_req_cookie("req_cookie_a", "req_cookie_value_a")
           |> put_req_cookie("req_cookie_b", "req_cookie_value_b")

    response_cookies = %{"resp_cookie_a" => "resp_cookie_value_a",
                         "resp_cookie_b" => "resp_cookie_value_b"}
    conn = Enum.reduce response_cookies, conn, fn({key, value}, acc) ->
             Plug.Conn.put_resp_cookie(acc, key, value)
           end

    new_conn = recycle(conn)

    default = %Plug.Conn{}
    assert new_conn.assigns == default.assigns
    assert new_conn.before_send == default.before_send
    assert new_conn.cookies == default.cookies # unfetched
    assert new_conn.host == default.host
    assert new_conn.method == default.method
    assert new_conn.params == default.params # unfetched
    assert new_conn.path_info == default.path_info
    assert new_conn.private == default.private
    assert new_conn.query_string == default.query_string
    assert new_conn.req_cookies == default.req_cookies # unfetched
    assert new_conn.resp_body == default.resp_body
    assert new_conn.resp_cookies == default.resp_cookies
    assert new_conn.resp_headers == default.resp_headers
    assert new_conn.scheme == default.scheme
    assert new_conn.script_name == default.script_name
    assert new_conn.state == default.state
    assert new_conn.status == default.status

    assert new_conn.port == 80
    assert new_conn.adapter == {Plug.Adapters.Test.Conn, %{chunks: nil, method: "GET", params: nil, req_body: ""}}

    # test the actual contents of fetched fields
    fetched_default  = default  |> Plug.Conn.fetch_params |> Plug.Conn.fetch_cookies
    fetched_new_conn = new_conn |> Plug.Conn.fetch_params |> Plug.Conn.fetch_cookies
    assert fetched_new_conn.params == fetched_default.params

    # previous response cookies should be copied into the request cookies
    assert fetched_new_conn.cookies == response_cookies
    assert fetched_new_conn.req_cookies == response_cookies
  end
end
