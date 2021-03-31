defmodule Plug.Conn.AdapterTest do
  use ExUnit.Case, async: true

  test "conn/5" do
    conn =
      Plug.Conn.Adapter.conn(
        {__MODULE__, :meta},
        "POST",
        URI.parse("https://example.com/bar//baz?bat"),
        {127, 0, 0, 1},
        [{"foo", "bar"}]
      )

    assert conn.adapter == {__MODULE__, :meta}
    assert conn.method == "POST"
    assert conn.host == "example.com"
    assert conn.scheme == :https
    assert conn.request_path == "/bar//baz"
    assert conn.query_string == "bat"
    assert conn.path_info == ["bar", "baz"]
    assert conn.remote_ip == {127, 0, 0, 1}
    assert conn.req_headers == [{"foo", "bar"}]
  end
end
