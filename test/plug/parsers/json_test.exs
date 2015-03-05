defmodule Phoenix.Parsers.JSONTest do
  use ExUnit.Case, async: true
  use Plug.Test

  defmodule JSON do
    def decode!("[1, 2, 3]") do
      [1, 2, 3]
    end

    def decode!("{id: 1}") do
      %{"id" => 1}
    end

    def decode!(_) do
      raise "oops"
    end
  end

  def parse(conn, opts \\ []) do
    opts = opts
           |> Keyword.put_new(:parsers, [:json])
           |> Keyword.put_new(:json_decoder, JSON)
    Plug.Parsers.call(conn, Plug.Parsers.init(opts))
  end

  test "parses the request body" do
    headers = [{"content-type", "application/json"}]
    conn = parse(conn(:post, "/", "{id: 1}", headers: headers))
    assert conn.params["id"] == 1
  end

  test "parses the request body when it is an array" do
    headers = [{"content-type", "application/json"}]
    conn = parse(conn(:post, "/", "[1, 2, 3]", headers: headers))
    assert conn.params["_json"] == [1, 2, 3]
  end

  test "handles empty body as blank map" do
    headers = [{"content-type", "application/json"}]
    conn = parse(conn(:post, "/", nil, headers: headers))
    assert conn.params == %{}
  end

  test "parses json-parseable content types" do
    headers = [{"content-type", "application/vnd.api+json"}]
    conn = parse(conn(:post, "/", "{id: 1}", headers: headers))
    assert conn.params["id"] == 1
  end

  test "expects a json encoder" do
    headers = [{"content-type", "application/json"}]
    assert_raise ArgumentError, "JSON parser expects a :json_decoder option", fn ->
      parse(conn(:post, "/", nil, headers: headers), json_decoder: nil)
    end
  end

  test "raises on too large bodies" do
    exception = assert_raise Plug.Parsers.RequestTooLargeError, fn ->
      headers = [{"content-type", "application/json"}]
      parse(conn(:post, "/", "foo=baz", headers: headers), length: 5)
    end
    assert Plug.Exception.status(exception) == 413
  end

  test "raises ParseError with malformed JSON" do
    exception = assert_raise Plug.Parsers.ParseError,
                             ~r/malformed request, got RuntimeError with message oops/, fn ->
      headers = [{"content-type", "application/json"}]
      parse(conn(:post, "/", "invalid json", headers: headers))
    end
    assert Plug.Exception.status(exception) == 400
  end
end
