defmodule Plug.ParsersTest do
  use ExUnit.Case, async: true

  import Plug.Test

  def parse(conn, opts \\ []) do
    opts = Keyword.put_new(opts, :parsers, [Plug.Parsers.URLENCODED, Plug.Parsers.MULTIPART])
    Plug.Parsers.call(conn, Plug.Parsers.init(opts))
  end

  test "raises when no parsers is given" do
    assert_raise ArgumentError, fn ->
      parse(conn(:post, "/"), parsers: nil)
    end
  end

  test "parses query string information" do
    conn = parse(conn(:post, "/?foo=bar"))
    assert conn.params["foo"] == "bar"
  end

  test "ignore bodies unless post/put/match" do
    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    conn = parse(conn(:get, "/?foo=bar", "foo=baz", headers: headers))
    assert conn.params["foo"] == "bar"
  end

  test "parses url encoded bodies" do
    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    conn = parse(conn(:post, "/?foo=bar", "foo=baz", headers: headers))
    assert conn.params["foo"] == "baz"
  end

  test "parses multipart bodies" do
    conn = parse(conn(:post, "/?foo=bar", [foo: "baz"]))
    assert conn.params["foo"] == "baz"
  end

  test "raises on too large bodies" do
    exception = assert_raise Plug.Parsers.RequestTooLargeError, fn ->
      headers = [{"content-type", "application/x-www-form-urlencoded"}]
      parse(conn(:post, "/?foo=bar", "foo=baz", headers: headers), length: 5)
    end
    assert Plug.Exception.status(exception) == 413
  end

  test "raises when request cannot be processed" do
    exception = assert_raise Plug.Parsers.UnsupportedMediaTypeError, fn ->
      headers = [{"content-type", "text/plain"}]
      parse(conn(:post, "/?foo=bar", "foo=baz", headers: headers))
    end
    assert Plug.Exception.status(exception) == 415
  end

  test "does not raise when request cannot be processed if accepts all mimes" do
    headers = [{"content-type", "text/plain"}]
    conn = parse(conn(:post, "/?foo=bar", "foo=baz", headers: headers), accept: ["*/*"])
    assert conn.params["foo"] == "bar"
  end

  test "does not raise when request cannot be processed if mime accepted" do
    headers = [{"content-type", "text/plain"}]
    conn = parse(conn(:post, "/?foo=bar", "foo=baz", headers: headers), accept: [
      "text/plain", "application/json"
    ])
    assert conn.params["foo"] == "bar"

    headers = [{"content-type", "application/json"}]
    conn = parse(conn(:post, "/?foo=bar", "foo=baz", headers: headers), accept: [
      "text/plain", "application/json"
    ])
    assert conn.params["foo"] == "bar"
  end

  test "does not raise when request cannot be processed if accepts mime range" do
    headers = [{"content-type", "text/plain"}]
    conn = parse(conn(:post, "/?foo=bar", "foo=baz", headers: headers), accept: ["text/*"])
    assert conn.params["foo"] == "bar"
  end

  test "raises when request cannot be processed if mime range not accepted" do
    exception = assert_raise Plug.Parsers.UnsupportedMediaTypeError, fn ->
      headers = [{"content-type", "application/json"}]
      parse(conn(:post, "/?foo=bar", "foo=baz", headers: headers), accept: ["text/*"])
    end
    assert Plug.Exception.status(exception) == 415
  end

end
