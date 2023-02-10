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

    def decode!(~s({query: "fooBAR"})) do
      %{"query" => "fooBAR"}
    end

    def decode!(~s({query: "fooBAZ"})) do
      %{"query" => "fooBAZ"}
    end

    def decode!(~s("str")) do
      "str"
    end

    def decode!(~s(1)) do
      1
    end

    def decode!(~s(false)) do
      false
    end

    def decode!(~s(null)) do
      nil
    end

    def decode!("[]") do
      []
    end

    def decode!("{_json: []}") do
      %{"_json" => []}
    end

    def decode!(_) do
      raise "oops"
    end

    def decode!("{id: 1}", capitalize_keys: true) do
      %{"ID" => 1}
    end
  end

  defmodule BodyReader do
    def read_body(conn, opts) do
      {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
      {:ok, String.replace(body, "foo", "fooBAR"), conn}
    end

    def read_body(conn, opts, "test", "read body") do
      {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
      {:ok, String.replace(body, "foo", "fooBAZ"), conn}
    end
  end

  def json_conn(body, content_type \\ "application/json") do
    put_req_header(conn(:post, "/", body), "content-type", content_type)
  end

  def parse(conn, opts \\ []) do
    opts =
      opts
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

  test "parses the request body when it is a scalar" do
    conn = ~s("str") |> json_conn() |> parse()
    assert conn.params["_json"] == "str"
  end

  test "parses the request body when it is a number" do
    conn = ~s(1) |> json_conn() |> parse()
    assert conn.params["_json"] == 1
  end

  test "parses the request body when it is a boolean" do
    conn = ~s(false) |> json_conn() |> parse()
    assert conn.params["_json"] == false
  end

  test "parses the request body when it is null" do
    conn = ~s(null) |> json_conn() |> parse()
    assert conn.params["_json"] == nil
  end

  test "parses json-parseable content types" do
    conn = "{id: 1}" |> json_conn("application/vnd.api+json") |> parse()
    assert conn.params["id"] == 1
  end

  test "parses with decoder as a MFA argument" do
    conn =
      "{id: 1}"
      |> json_conn()
      |> parse(json_decoder: {JSON, :decode!, [[capitalize_keys: true]]})

    assert conn.params["ID"] == 1
  end

  test "parses with custom body reader" do
    conn =
      ~s({query: "foo"})
      |> json_conn()
      |> parse(body_reader: {BodyReader, :read_body, []})

    assert conn.params["query"] == "fooBAR"
  end

  test "parses with custom body reader and extra args" do
    conn =
      ~s({query: "foo"})
      |> json_conn()
      |> parse(body_reader: {BodyReader, :read_body, ["test", "read body"]})

    assert conn.params["query"] == "fooBAZ"
  end

  test "expects a json decoder" do
    assert_raise ArgumentError, "JSON parser expects a :json_decoder option", fn ->
      nil |> json_conn() |> parse(json_decoder: nil)
    end
  end

  test "validates the json decoder (expressed as a MFA tuple)" do
    message =
      "invalid :json_decoder option. The module Plug.Parsers.JSONTest.JSON must implement test/2"

    assert_raise ArgumentError, message, fn ->
      nil |> json_conn() |> parse(json_decoder: {JSON, :test, [[capitalize_keys: true]]})
    end
  end

  test "validates the json decoder (expressed as a module)" do
    message =
      "invalid :json_decoder option. The module InexistentJSONDecoder is not loaded " <>
        "and could not be found"

    assert_raise ArgumentError, message, fn ->
      nil |> json_conn() |> parse(json_decoder: InexistentJSONDecoder)
    end

    defmodule InvalidJSONDecoder do
    end

    message =
      "invalid :json_decoder option. The module Plug.Parsers.JSONTest.InvalidJSONDecoder " <>
        "must implement decode!/1"

    assert_raise ArgumentError, message, fn ->
      nil |> json_conn() |> parse(json_decoder: InvalidJSONDecoder)
    end
  end

  test "raises on too large bodies" do
    exception =
      assert_raise Plug.Parsers.RequestTooLargeError, fn ->
        "foo=baz" |> json_conn() |> parse(length: 5)
      end

    assert Plug.Exception.status(exception) == 413
  end

  test "raises ParseError with malformed JSON" do
    message = ~s(malformed request, a RuntimeError exception was raised with message "oops")

    exception =
      assert_raise Plug.Parsers.ParseError, message, fn ->
        "invalid json" |> json_conn() |> parse()
      end

    assert Plug.Exception.status(exception) == 400
  end

  test "nests all json when nest_all_json is true" do
    conn_object = "{_json: []}" |> json_conn() |> parse(nest_all_json: true)
    conn_array = "[]" |> json_conn() |> parse(nest_all_json: true)
    assert conn_object.params == %{"_json" => %{"_json" => []}}
    assert conn_array.params == %{"_json" => []}
  end
end
