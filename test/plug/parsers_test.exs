defmodule Plug.ParsersTest do
  use ExUnit.Case, async: true

  use Plug.Test

  defmodule BodyReader do
    def read_body(conn, opts) do
      {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
      {:ok, body <> "BAR", conn}
    end

    def read_body(conn, opts, "test", "read body") do
      {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
      {:ok, body <> "BAZ", conn}
    end
  end

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
    assert conn.body_params == %{}
    assert conn.query_params["foo"] == "bar"
  end

  test "parses query string information with limit" do
    assert_raise Plug.Conn.InvalidQueryError, fn ->
      parse(conn(:post, "/?foo=bar"), query_string_length: 5)
    end
  end

  test "keeps existing params" do
    conn = %{conn(:post, "/?query=foo", "body=bar") | params: %{"params" => "baz"}}

    conn =
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> parse()

    assert conn.params["query"] == "foo"
    assert conn.params["body"] == "bar"
    assert conn.params["params"] == "baz"
  end

  test "parsing prefers path params over body params" do
    conn =
      conn(:post, "/", "foo=body")
      |> Map.put(:params, %{"foo" => "bar"})
      |> Map.put(:path_params, %{"foo" => "path"})
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> parse()

    assert conn.params["foo"] == "path"
  end

  test "parsing prefers body params over query params with existing params" do
    conn =
      conn(:post, "/?foo=query", "foo=body")
      |> Map.put(:params, %{"foo" => "params"})
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> parse()

    assert conn.params["foo"] == "body"
  end

  test "keeps existing body params" do
    conn = conn(:post, "/?foo=bar")
    conn = parse(%{conn | body_params: %{"foo" => "baz"}, params: %{"foo" => "baz"}})
    assert conn.params["foo"] == "baz"
    assert conn.body_params["foo"] == "baz"
    assert conn.query_params["foo"] == "bar"
  end

  test "ignore bodies unless post/put/match/delete" do
    conn =
      conn(:get, "/?foo=bar", "foo=baz")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> parse()

    assert conn.params["foo"] == "bar"
    assert conn.body_params == %{}
    assert conn.query_params["foo"] == "bar"
  end

  test "error on invalid utf-8 in query params when merging params" do
    conn = conn(:post, "/?foo=#{<<139>>}")

    assert_raise Plug.Conn.InvalidQueryError,
                 "invalid UTF-8 on urlencoded params, got byte 139",
                 fn ->
                   parse(%{conn | body_params: %{"foo" => "baz"}, params: %{"foo" => "baz"}})
                 end
  end

  test "errors on invalid utf-8 in body params when validate_utf8 true (by default)" do
    conn =
      conn(:post, "/", "foo=#{<<139>>}")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")

    assert_raise(
      Plug.Parsers.BadEncodingError,
      "invalid UTF-8 on urlencoded params, got byte 139",
      fn ->
        parse(conn, validate_utf8: true)
      end
    )
  end

  test "errors on invalid utf-8 in body params with custom exception" do
    conn =
      conn(:post, "/", "foo=#{<<139>>}")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")

    assert_raise(
      ArgumentError,
      "invalid UTF-8 on urlencoded params, got byte 139",
      fn ->
        parse(conn, validate_utf8: ArgumentError)
      end
    )
  end

  test "parses invalid utf-8 in body params when validate_utf8 false" do
    conn =
      conn(:post, "/", "foo=#{<<139>>}")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> parse(validate_utf8: false)

    assert conn.params["foo"] == <<139>>
    assert conn.body_params["foo"] == <<139>>
  end

  test "parses url encoded bodies" do
    conn =
      conn(:post, "/?foo=bar", "foo=baz")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> parse()

    assert conn.params["foo"] == "baz"
  end

  test "parses multipart bodies with test params" do
    conn = parse(conn(:post, "/?foo=bar"))
    assert conn.params == %{"foo" => "bar"}

    conn = parse(conn(:post, "/?foo=bar", foo: "baz"))
    assert conn.params == %{"foo" => "baz"}
  end

  test "parses multipart bodies with test body" do
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
    Content-Disposition: form-data; name=\"doc\"; filename*=\"utf-8''%C5%BC%C3%B3%C5%82%C4%87.txt\"\r
    Content-Type: text/plain\r
    \r
    hello

    \r
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data\r
    \r
    skipped\r
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

    %{params: params} =
      conn(:post, "/", multipart)
      |> put_req_header("content-type", "multipart/mixed; boundary=----w58EW1cEpjzydSCq")
      |> parse()

    assert params["name"] == "hello"
    assert params["status"] == ["choice1", "choice2"]
    assert params["empty"] == nil

    assert %Plug.Upload{} = file = params["pic"]
    assert File.read!(file.path) == "hello\n\n"
    assert file.content_type == "text/plain"
    assert file.filename == "foo.txt"

    assert %Plug.Upload{} = file = params["doc"]
    assert File.read!(file.path) == "hello\n\n"
    assert file.content_type == "text/plain"
    assert file.filename == "żółć.txt"
  end

  def multipart_to_params(acc, conn) do
    params =
      acc
      |> List.foldr(Plug.Conn.Query.decode_init(), fn {name, headers, body}, acc ->
        Plug.Conn.Query.decode_each({name || "_parts[]", %{headers: headers, body: body}}, acc)
      end)
      |> Plug.Conn.Query.decode_done()

    {:ok, params, conn}
  end

  test "multipart with custom parameter conversion" do
    multipart = """
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"name\"\r
    \r
    hello\r
    ------w58EW1cEpjzydSCq\r
    Content-Type: application/json\r
    \r
    {"indisposed": "json"}\r
    ------w58EW1cEpjzydSCq\r
    Content-Type: application/octet-stream\r
    X-My-Foo: bar\r
    \r
    foo\r
    ------w58EW1cEpjzydSCq\r
    \r
    No content-type? No problem!\r
    ------w58EW1cEpjzydSCq--\r
    """

    %{params: params} =
      conn(:post, "/", multipart)
      |> put_req_header("content-type", "multipart/mixed; boundary=----w58EW1cEpjzydSCq")
      |> parse(multipart_to_params: {__MODULE__, :multipart_to_params, []})

    assert params["name"].headers == [{"content-disposition", "form-data; name=\"name\""}]
    assert params["name"].body == "hello"

    assert [part1, part2, part3] = params["_parts"]
    assert part1.body == "{\"indisposed\": \"json\"}"
    assert part1.headers == [{"content-type", "application/json"}]
    assert part2.body == "foo"
    assert part2.headers == [{"x-my-foo", "bar"}, {"content-type", "application/octet-stream"}]
    assert part3.body == "No content-type? No problem!"
    assert part3.headers == []
  end

  test "validates utf8 in multipart body" do
    latin1_binary = :unicode.characters_to_binary(~c"hello©", :utf8, :latin1)

    multipart = """
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"name\"\r
    \r
    #{latin1_binary}\r
    ------w58EW1cEpjzydSCq--\r
    """

    assert_raise Plug.Parsers.BadEncodingError, fn ->
      conn(:post, "/", multipart)
      |> put_req_header("content-type", "multipart/mixed; boundary=----w58EW1cEpjzydSCq")
      |> parse()
    end
  end

  test "does not validate utf8 in multipart body opt" do
    latin1_binary = :unicode.characters_to_binary(~c"hello©", :utf8, :latin1)

    multipart = """
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"name\"\r
    \r
    #{latin1_binary}\r
    ------w58EW1cEpjzydSCq--\r
    """

    %{params: params} =
      conn(:post, "/", multipart)
      |> put_req_header("content-type", "multipart/mixed; boundary=----w58EW1cEpjzydSCq")
      |> parse(validate_utf8: false)

    assert params["name"] == latin1_binary
  end

  test "parses empty multipart body" do
    %{params: params} =
      conn(:post, "/", "")
      |> put_req_header("content-type", "multipart/form-data")
      |> parse()

    assert params == %{}
  end

  test "parses with custom body reader" do
    conn = conn(:post, "/?query=elixir", "body=foo")

    conn =
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> parse(body_reader: {BodyReader, :read_body, []})

    assert conn.params["query"] == "elixir"
    assert conn.params["body"] == "fooBAR"
  end

  test "parses with custom body reader and extra args" do
    conn = conn(:post, "/?query=elixir", "body=foo")

    conn =
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> parse(body_reader: {BodyReader, :read_body, ["test", "read body"]})

    assert conn.params["query"] == "elixir"
    assert conn.params["body"] == "fooBAZ"
  end

  test "raises on invalid url encoded" do
    message = "invalid UTF-8 on urlencoded params, got byte 139"

    assert_raise Plug.Parsers.BadEncodingError, message, fn ->
      conn(:post, "/foo", "a=" <> <<139>>)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> parse()
    end
  end

  test "does not raise when url contains invalid utf-8 and validate_utf8 is false" do
    conn(:post, "/foo", "a=" <> <<139>>)
    |> parse(validate_utf8: false)
  end

  test "raises on too large bodies with root option" do
    exception =
      assert_raise Plug.Parsers.RequestTooLargeError, ~r/the request is too large/, fn ->
        conn(:post, "/?foo=bar", "foo=baz")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> parse(length: 5)
      end

    assert Plug.Exception.status(exception) == 413
  end

  test "raises on too large bodies with parser option" do
    exception =
      assert_raise Plug.Parsers.RequestTooLargeError, ~r/the request is too large/, fn ->
        conn(:post, "/?foo=bar", "foo=baz")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> parse(parsers: [urlencoded: [length: 5]])
      end

    assert Plug.Exception.status(exception) == 413
  end

  test "raises on too large bodies with parser specific defaults" do
    exception =
      assert_raise Plug.Parsers.RequestTooLargeError, ~r/the request is too large/, fn ->
        conn(:post, "/?foo=bar", String.duplicate("foo=baz", 200_000))
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> parse()
      end

    assert Plug.Exception.status(exception) == 413
  end

  test "raises when request cannot be processed" do
    message = "unsupported media type text/plain"

    exception =
      assert_raise Plug.Parsers.UnsupportedMediaTypeError, message, fn ->
        conn(:post, "/?foo=bar", "foo=baz")
        |> put_req_header("content-type", "text/plain")
        |> parse()
      end

    assert Plug.Exception.status(exception) == 415
  end

  test "raises when request cannot be processed and if mime range not accepted" do
    exception =
      assert_raise Plug.Parsers.UnsupportedMediaTypeError, fn ->
        conn(:post, "/?foo=bar", "foo=baz")
        |> put_req_header("content-type", "application/json")
        |> parse(pass: ["text/plain", "text/*"])
      end

    assert Plug.Exception.status(exception) == 415
  end

  test "raises when request cannot be processed and if mime is invalid" do
    exception =
      assert_raise Plug.Parsers.UnsupportedMediaTypeError, fn ->
        conn(:post, "/?foo=bar", "foo=baz")
        |> put_req_header("content-type", "invalid")
        |> parse(pass: ["text/plain", "text/*"])
      end

    assert Plug.Exception.status(exception) == 415
  end

  test "does not raise when request cannot be processed if accepts all mimes" do
    conn =
      conn(:post, "/?foo=bar", "foo=baz")
      |> put_req_header("content-type", "text/plain")
      |> Map.put(:path_params, %{"bar" => "baz"})
      |> parse(pass: ["*/*"])

    assert conn.params["foo"] == "bar"
    assert conn.params["bar"] == "baz"
    assert conn.body_params == %Plug.Conn.Unfetched{aspect: :body_params}
  end

  test "does not raise when request cannot be processed if mime accepted" do
    conn =
      conn(:post, "/?foo=bar", "foo=baz")
      |> put_req_header("content-type", "text/plain")
      |> parse(pass: ["text/plain", "application/json"])

    assert conn.params["foo"] == "bar"
    assert conn.body_params == %Plug.Conn.Unfetched{aspect: :body_params}

    conn =
      conn(:post, "/?foo=bar", "foo=baz")
      |> put_req_header("content-type", "application/json")
      |> parse(pass: ["text/plain", "application/json"])

    assert conn.params["foo"] == "bar"
    assert conn.body_params == %Plug.Conn.Unfetched{aspect: :body_params}
  end

  test "does not raise when request cannot be processed if accepts mime range" do
    conn =
      conn(:post, "/?foo=bar", "foo=baz")
      |> put_req_header("content-type", "text/plain")
      |> parse(pass: ["text/plain", "text/*"])

    assert conn.params["foo"] == "bar"
    assert conn.body_params == %Plug.Conn.Unfetched{aspect: :body_params}
  end
end
