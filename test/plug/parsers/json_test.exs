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
    put_req_header(conn(:post, "/", body), "content-type", content_type)
  end

  def parse(conn, opts \\ []) do
    opts = opts
           |> Keyword.put_new(:parsers, [:json])
           |> Keyword.put_new(:json_decoder, JSON)
    Plug.Parsers.call(conn, Plug.Parsers.init(opts))
  end

  test "parses the request body" do
    conn = "{id: 1}" |> json_conn() |> parse()
    assert conn.params["id"] == 1
  end

  test "parses the request body when it is an array" do
    conn = "[1, 2, 3]" |> json_conn() |> parse()
    assert conn.params["_json"] == [1, 2, 3]
  end

  test "handles empty body as blank map" do
    conn = nil |> json_conn() |> parse()
    assert conn.params == %{}
  end

  test "parses json-parseable content types" do
    conn = "{id: 1}" |> json_conn("application/vnd.api+json") |> parse()
    assert conn.params["id"] == 1
  end

  test "parses with decoder as a function" do
    conn = "{id: 1}" |> json_conn() |> parse([json_decoder: &JSON.decode!/1])
    assert conn.params["id"] == 1
  end

  test "expects a json encoder" do
    assert_raise ArgumentError, "JSON parser expects a :json_decoder option", fn ->
      nil |> json_conn() |> parse(json_decoder: nil)
    end
  end

  test "raises on too large bodies" do
    exception = assert_raise Plug.Parsers.RequestTooLargeError, fn ->
      "foo=baz" |> json_conn() |> parse(length: 5)
    end
    assert Plug.Exception.status(exception) == 413
  end

  test "raises ParseError with malformed JSON" do
    message = ~s(malformed request, a RuntimeError exception was raised with message "oops")
    exception = assert_raise Plug.Parsers.ParseError, message, fn ->
      "invalid json" |> json_conn() |> parse()
    end
    assert Plug.Exception.status(exception) == 400
  end
end
