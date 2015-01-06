defmodule Plug.StaticTest do
  use ExUnit.Case, async: true
  use Plug.Test

  @cache_header "public, max-age=31536000"

  defmodule MyPlug do
    use Plug.Builder

    plug Plug.Static,
      at: "/public",
      from: Path.expand("..", __DIR__),
      gzip: true

    plug :passthrough

    defp passthrough(conn, _), do:
      Plug.Conn.send_resp(conn, 404, "Passthrough")
  end

  defmodule MyPlugNoCache do
    use Plug.Builder

    plug Plug.Static,
      at: "/public",
      from: Path.expand("..", __DIR__),
      cache_control_for_query_strings: false
    plug :passthrough

    defp passthrough(conn, _), do:
      Plug.Conn.send_resp(conn, 404, "Passthrough")
  end

  defp call(conn), do: MyPlug.call(conn, [])

  test "serves the file" do
    conn = conn(:get, "/public/fixtures/static.txt") |> call
    assert conn.status == 200
    assert conn.resp_body == "HELLO"
    assert get_resp_header(conn, "content-type")  == ["text/plain"]
    assert_non_empty_etag_header(conn)
  end

  test "serves the file with a urlencoded filename" do
    conn = conn(:get, "/public/fixtures/static%20with%20spaces.txt") |> call
    assert conn.status == 200
    assert conn.resp_body == "SPACES"
    assert get_resp_header(conn, "content-type")  == ["text/plain"]
    assert_non_empty_etag_header(conn)
  end

  test "sets the cache-control header only if there's a query string" do
    conn = conn(:get, "/public/fixtures/static.txt?foo=bar") |> call
    assert conn.status == 200
    assert conn.resp_body == "HELLO"
    assert get_resp_header(conn, "content-type")  == ["text/plain"]

    assert get_resp_header(conn, "cache-control") == [@cache_header]
    assert get_resp_header(conn, "etag") == []
  end

  test "doesnt set cache headers" do
    conn = conn(:get, "/public/fixtures/static.txt") |> MyPlugNoCache.call([])
    assert conn.status == 200
    refute get_resp_header(conn, "cache-control") == [@cache_header]
    assert get_resp_header(conn, "etag") == []
  end

  test "passes through on other paths" do
    conn = conn(:get, "/another/fallback.txt") |> call
    assert conn.status == 404
    assert conn.resp_body == "Passthrough"
  end

  test "passes through on non existing files" do
    conn = conn(:get, "/public/fixtures/unknown.txt") |> call
    assert conn.status == 404
    assert conn.resp_body == "Passthrough"
  end

  test "passes through on directories" do
    conn = conn(:get, "/public/fixtures") |> call
    assert conn.status == 404
    assert conn.resp_body == "Passthrough"
  end

  test "passes for non-get/non-head requests" do
    conn = conn(:post, "/public/fixtures/static.txt") |> call
    assert conn.status == 404
    assert conn.resp_body == "Passthrough"
  end

  test "returns 400 for unsafe paths" do
    exception = assert_raise Plug.Static.InvalidPathError,
                             "invalid path for static asset", fn ->
      conn(:get, "/public/fixtures/../fixtures/static/file.txt") |> call
    end

    assert Plug.Exception.status(exception) == 400

    exception = assert_raise Plug.Static.InvalidPathError,
                             "invalid path for static asset", fn ->
      conn(:get, "/public/c:\\foo.txt") |> call
    end

    assert Plug.Exception.status(exception) == 400
  end

  test "serves gzipped file" do
    conn = call conn(:get, "/public/fixtures/static.txt", [],
                     headers: [{"accept-encoding", "gzip"}])
    assert conn.status == 200
    assert conn.resp_body == "GZIPPED HELLO"
    assert get_resp_header(conn, "content-encoding") == ["gzip"]

    conn = call conn(:get, "/public/fixtures/static.txt", [],
                     headers: [{"accept-encoding", "*"}])
    assert conn.status == 200
    assert conn.resp_body == "GZIPPED HELLO"
    assert get_resp_header(conn, "content-encoding") == ["gzip"]
  end

  test "only serves gzipped file if available" do
    conn = call conn(:get, "/public/fixtures/static%20with%20spaces.txt", [],
                     headers: [{"accept-encoding", "gzip"}])
    assert conn.status == 200
    assert conn.resp_body == "SPACES"
    assert get_resp_header(conn, "content-encoding") != ["gzip"]
  end

  test "raises an exception if :from isn't a binary or an atom" do
    assert_raise ArgumentError, fn ->
      defmodule ExceptionPlug do
        use Plug.Builder
        plug Plug.Static, from: 42, at: "foo"
      end
    end
  end

  defp assert_non_empty_etag_header(conn) do
    etag_length = conn |> get_resp_header("etag") |> hd |> String.length
    assert etag_length > 0
  end
end
