defmodule Plug.Parsers.JSONTest do
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

  def json_conn(body, content_type \\ "application/json") do
    conn(:post, "/", body) |> put_req_header("content-type", content_type)
  end

  def parse(conn, opts \\ []) do
    opts = opts
           |> Keyword.put_new(:parsers, [:json])
           |> Keyword.put_new(:json_decoder, JSON)
    Plug.Parsers.call(conn, Plug.Parsers.init(opts))
  end

  test "parses the request body" do
    conn = json_conn("{id: 1}") |> parse()
    assert conn.params["id"] == 1
  end

  test "parses the request body when it is an array" do
    conn = json_conn("[1, 2, 3]") |> parse()
    assert conn.params["_json"] == [1, 2, 3]
  end

  test "handles empty body as blank map" do
    conn = json_conn(nil) |> parse()
    assert conn.params == %{}
  end

  test "parses json-parseable content types" do
    conn = json_conn("{id: 1}", "application/vnd.api+json") |> parse()
    assert conn.params["id"] == 1
  end

  test "expects a json encoder" do
    assert_raise ArgumentError, "JSON parser expects a :json_decoder option", fn ->
      json_conn(nil) |> parse(json_decoder: nil)
    end
  end

  test "raises on too large bodies" do
    exception = assert_raise Plug.Parsers.RequestTooLargeError, fn ->
      json_conn("foo=baz") |> parse(length: 5)
    end
    assert Plug.Exception.status(exception) == 413
  end

  test "raises ParseError with malformed JSON" do
    message = ~s(malformed request, a RuntimeError exception was raised with message: "oops")
    exception = assert_raise Plug.Parsers.ParseError, message, fn ->
      json_conn("invalid json") |> parse()
    end
    assert Plug.Exception.status(exception) == 400
  end
end
