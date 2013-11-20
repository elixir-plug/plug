defmodule Plug.Adapters.Test.ConnectionTest do
  use ExUnit.Case, async: true

  import Plug.Test

  test "stream_req_body/2" do
    conn = conn(:get, "/", "abcdefgh", headers: [{ "content-type", "text/plain" }])
    { adapter, state } = conn.adapter
    assert { :ok, "abcde", state } = adapter.stream_req_body(state, 5)
    assert { :ok, "fgh", state } = adapter.stream_req_body(state, 5)
    assert { :done, state } = adapter.stream_req_body(state, 5)
    assert { :done, state } = adapter.stream_req_body(state, 5)
    conn.adapter({ adapter, state })
  end

  test "custom body requires content-type" do
    assert_raise ArgumentError, fn ->
      conn(:get, "/", "abcdefgh")
    end
  end

  test "custom params sets content-type to multipart/mixed" do
    conn = conn(:get, "/", foo: "bar")
    assert conn.req_headers == [{ "content-type", "multipart/mixed; charset: utf-8" }]
  end

  test "parse_req_multipart/4" do
    conn = conn(:get, "/", a: "b", c: [[d: "e"], "f"])
    { adapter, state } = conn.adapter
    assert { :ok, params, state } = adapter.parse_req_multipart(state, 1_000_000, [{ "a", "oops" }], fn _ -> end)
    assert params == [{ "a", "b" }, { "c", [[{ "d", "e" }], "f"] }]
    conn.adapter({ adapter, state })
  end
end
