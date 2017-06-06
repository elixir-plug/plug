defmodule Plug.Adapters.Test.ConnTest do
  use ExUnit.Case, async: true

  import Plug.Test

  test "read_req_body/2" do
    conn = conn(:get, "/", "abcdefghij")
    {adapter, state} = conn.adapter

    assert {:more, "abcde", state} = adapter.read_req_body(state, length: 5)
    assert {:more, "f", state} = adapter.read_req_body(state, length: 1)
    assert {:more, "gh", state} = adapter.read_req_body(state, length: 2)
    assert {:ok, "ij", state} = adapter.read_req_body(state, length: 5)
    assert {:ok, "", _state} = adapter.read_req_body(state, length: 5)
  end

  test "custom params" do
    conn = conn(:get, "/", a: "b", c: [%{d: "e"}])
    assert conn.params == %{"a" => "b", "c" => [%{"d" => "e"}]}

    conn = conn(:get, "/", a: "b", c: [d: "e"])
    assert conn.params == %{"a" => "b", "c" => %{"d" => "e"}}

    conn = conn(:post, "/?foo=bar", %{foo: "baz"})
    assert conn.params == %{"foo" => "baz"}
  end

  test "custom struct params" do
    conn = conn(:get, "/", a: "b", file: %Plug.Upload{})
    assert conn.params == %{"a" => "b", "file" => %Plug.Upload{content_type: nil, filename: nil, path: nil}}

    conn = conn(:get, "/", a: "b", file: %{__struct__: "Foo"})
    assert conn.params == %{"a" => "b", "file" => %{"__struct__" => "Foo"}}
  end

  test "no body or params" do
    conn = conn(:get, "/")
    {adapter, state} = conn.adapter
    assert conn.req_headers == []
    assert {:ok, "", _state} = adapter.read_req_body(state, length: 10)
  end

  test "custom params sets content-type to multipart/mixed when content-type is not set" do
    conn = conn(:get, "/", foo: "bar")
    assert conn.req_headers == [{"content-type", "multipart/mixed; charset: utf-8"}]
  end

  test "custom params does not change content-type when set" do
    conn =
      conn(:get, "/", foo: "bar")
      |> Plug.Conn.put_req_header("content-type", "application/vnd.api+json")
      |> Plug.Adapters.Test.Conn.conn(:get, "/", foo: "bar")
    assert conn.req_headers == [{"content-type", "application/vnd.api+json"}]
  end

  test "parse_req_multipart/4" do
    multipart = """
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"name\"\r
    \r
    hello\r
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"pic\"; filename=\"foo.txt\"\r
    Content-Type: text/plain\r
    \r
    hello

    \r
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"empty\"; filename=\"\"\r
    Content-Type: application/octet-stream\r
    \r
    \r
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name="status[]"\r
    \r
    choice1\r
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name="status[]"\r
    \r
    choice2\r
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"commit\"\r
    \r
    Create User\r
    ------w58EW1cEpjzydSCq--\r
    """

    conn = conn(:post, "/")

    {adapter, _state} = conn.adapter

    assert {:ok, params, _} = adapter.parse_req_multipart(%{req_body: multipart}, [{:boundary, "----w58EW1cEpjzydSCq"}], &Plug.Parsers.MULTIPART.handle_headers/1)

    assert params["name"] == "hello"
    assert params["status"] == ["choice1", "choice2"]
    assert params["empty"] == nil

    assert %Plug.Upload{} = file = params["pic"]
    assert File.read!(file.path) == "hello\n\n"
    assert file.content_type == "text/plain"
    assert file.filename == "foo.txt"
  end

  test "use existing conn.host if exists" do
    conn_with_host = conn(:get, "http://www.elixir-lang.org/")
    assert conn_with_host.host == "www.elixir-lang.org"

    child_conn = Plug.Adapters.Test.Conn.conn(conn_with_host, :get, "/getting-started/", nil)
    assert child_conn.host == "www.elixir-lang.org"
  end

  test "full URL overrides existing conn.host" do
    conn_with_host = conn(:get, "http://www.elixir-lang.org/")
    assert conn_with_host.host == "www.elixir-lang.org"

    child_conn = Plug.Adapters.Test.Conn.conn(conn_with_host, :get, "http://www.example.org/", nil)
    assert child_conn.host == "www.example.org"
  end

  test "use existing conn.remote_ip if exists" do
    conn_with_remote_ip = %Plug.Conn{conn(:get, "/") | remote_ip: {151, 236, 219, 228}}
    child_conn = Plug.Adapters.Test.Conn.conn(conn_with_remote_ip, :get, "/", foo: "bar")
    assert child_conn.remote_ip == {151, 236, 219, 228}
  end
end
