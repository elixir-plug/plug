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
end
