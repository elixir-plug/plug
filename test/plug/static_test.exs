defmodule Plug.StaticTest do
  use ExUnit.Case, async: true
  use Plug.Test

  defmodule MyPlug do
    use Plug.Builder

    plug Plug.Static,
      at: "/public",
      from: Path.expand("..", __DIR__),
      gzip: true,
      headers: %{"x-custom" => "x-value"},
      content_types: %{"manifest-file" => "application/vnd.manifest+json"}

    plug :passthrough

    defp passthrough(conn, _), do: Plug.Conn.send_resp(conn, 404, "Passthrough")
  end

  defp call(conn), do: MyPlug.call(conn, [])

  test "serves the file" do
    conn = call(conn(:get, "/public/fixtures/static.txt"))
    assert conn.status == 200
    assert conn.resp_body == "HELLO"
    assert get_resp_header(conn, "content-type") == ["text/plain"]
  end

  test "serves the file with a custom content type" do
    conn = call(conn(:get, "/public/fixtures/manifest-file"))
    assert conn.status == 200
    assert conn.resp_body == "[]"
    assert get_resp_header(conn, "content-type") == ["application/vnd.manifest+json"]
  end

  test "serves the file with a urlencoded filename" do
    conn = call(conn(:get, "/public/fixtures/static%20with%20spaces.txt"))
    assert conn.status == 200
    assert conn.resp_body == "SPACES"
    assert get_resp_header(conn, "content-type") == ["text/plain"]
  end

  test "performs etag negotiation" do
    conn = call(conn(:get, "/public/fixtures/static.txt"))
    assert conn.status == 200
    assert conn.resp_body == "HELLO"
    assert get_resp_header(conn, "content-type") == ["text/plain"]
    assert get_resp_header(conn, "x-custom") == ["x-value"]

    assert [etag] = get_resp_header(conn, "etag")
    assert String.first(etag) == "\""
    assert String.at(etag, String.length(etag) - 1) == "\""
    assert get_resp_header(conn, "cache-control") == ["public"]

    conn =
      conn(:get, "/public/fixtures/static.txt", nil)
      |> put_req_header("if-none-match", etag)
      |> call

    assert conn.status == 304
    assert conn.resp_body == ""
    assert get_resp_header(conn, "cache-control") == ["public"]
    assert get_resp_header(conn, "x-custom") == []
    assert get_resp_header(conn, "vary") == ["Accept-Encoding"]

    assert get_resp_header(conn, "content-type") == []
    assert get_resp_header(conn, "content-encoding") == []
    assert get_resp_header(conn, "etag") == [etag]
  end

  test "performs etag negotiation for gzip encoded files" do
    conn =
      conn(:get, "/public/fixtures/static.txt", [])
      |> put_req_header("accept-encoding", "gzip")
      |> call

    assert conn.status == 200
    assert conn.resp_body == "GZIPPED HELLO"
    assert get_resp_header(conn, "content-encoding") == ["gzip"]
    assert get_resp_header(conn, "vary") == ["Accept-Encoding"]
    assert get_resp_header(conn, "x-custom") == ["x-value"]

    assert [etag] = get_resp_header(conn, "etag")
    assert String.first(etag) == "\""
    assert String.at(etag, String.length(etag) - 1) == "\""
    assert get_resp_header(conn, "cache-control") == ["public"]

    conn =
      conn(:get, "/public/fixtures/static.txt", [])
      |> put_req_header("accept-encoding", "gzip")
      |> put_req_header("if-none-match", etag)
      |> call

    assert conn.status == 304
    assert conn.resp_body == ""
    assert get_resp_header(conn, "cache-control") == ["public"]
    assert get_resp_header(conn, "x-custom") == []
    assert get_resp_header(conn, "vary") == ["Accept-Encoding"]

    assert get_resp_header(conn, "content-type") == []
    assert get_resp_header(conn, "content-encoding") == []
    assert get_resp_header(conn, "etag") == [etag]
  end

  defmodule EtagGenerator do
    def generate(path, a, b) do
      {:ok, contents} = :prim_file.read_file(path)
      (contents |> :erlang.phash2() |> Integer.to_string(16)) <> "#{a}#{b}"
    end
  end

  test "performs etag negotiation with user defined etag generation" do
    opts = [
      at: "/public",
      from: Path.expand("..", __DIR__),
      etag_generation: {EtagGenerator, :generate, ["x", "y"]}
    ]

    conn = Plug.Static.call(conn(:get, "/public/fixtures/static.txt"), Plug.Static.init(opts))

    assert conn.status == 200
    assert conn.resp_body == "HELLO"
    assert get_resp_header(conn, "content-type") == ["text/plain"]
    assert [etag] = get_resp_header(conn, "etag")

    assert etag ==
             EtagGenerator.generate(Path.expand("../fixtures/static.txt", __DIR__), "x", "y")

    assert get_resp_header(conn, "cache-control") == ["public"]

    conn =
      conn(:get, "/public/fixtures/static.txt", nil)
      |> put_req_header("if-none-match", etag)
      |> Plug.Static.call(Plug.Static.init(opts))

    assert conn.status == 304
    assert conn.resp_body == ""
    assert get_resp_header(conn, "cache-control") == ["public"]
    assert get_resp_header(conn, "content-type") == []
    assert get_resp_header(conn, "content-encoding") == []
    assert get_resp_header(conn, "etag") == [etag]
  end

  test "sets the cache-control_for_vsn_requests when there's a query string" do
    conn = call(conn(:get, "/public/fixtures/static.txt?vsn=bar"))
    assert conn.status == 200
    assert conn.resp_body == "HELLO"
    assert get_resp_header(conn, "content-type") == ["text/plain"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000"]
    assert get_resp_header(conn, "etag") == []
    assert get_resp_header(conn, "x-custom") == ["x-value"]
  end

  test "doesn't set cache control headers" do
    opts = [
      at: "/public",
      from: Path.expand("..", __DIR__),
      cache_control_for_vsn_requests: nil,
      cache_control_for_etags: nil,
      headers: %{"x-custom" => "x-value"}
    ]

    conn = Plug.Static.call(conn(:get, "/public/fixtures/static.txt"), Plug.Static.init(opts))

    assert conn.status == 200
    assert get_resp_header(conn, "cache-control") == ["max-age=0, private, must-revalidate"]
    assert get_resp_header(conn, "etag") == []
    assert get_resp_header(conn, "x-custom") == ["x-value"]
  end

  test "passes through on other paths" do
    conn = call(conn(:get, "/another/fallback.txt"))
    assert conn.status == 404
    assert conn.resp_body == "Passthrough"
    assert get_resp_header(conn, "x-custom") == []
  end

  test "passes through on non existing files" do
    conn = call(conn(:get, "/public/fixtures/unknown.txt"))
    assert conn.status == 404
    assert conn.resp_body == "Passthrough"
    assert get_resp_header(conn, "x-custom") == []
  end

  test "passes through on directories" do
    conn = call(conn(:get, "/public/fixtures"))
    assert conn.status == 404
    assert conn.resp_body == "Passthrough"
    assert get_resp_header(conn, "x-custom") == []
  end

  test "passes for non-get/non-head requests" do
    conn = call(conn(:post, "/public/fixtures/static.txt"))
    assert conn.status == 404
    assert conn.resp_body == "Passthrough"
    assert get_resp_header(conn, "x-custom") == []
  end

  test "passes through does not check path validity" do
    conn = call(conn(:get, "/another/fallback%2Ftxt"))
    assert conn.status == 404
    assert conn.resp_body == "Passthrough"
    assert get_resp_header(conn, "x-custom") == []
  end

  test "returns 400 for unsafe paths" do
    exception =
      assert_raise Plug.Static.InvalidPathError, "invalid path for static asset", fn ->
        call(conn(:get, "/public/fixtures/../fixtures/static/file.txt"))
      end

    assert Plug.Exception.status(exception) == 400

    exception =
      assert_raise Plug.Static.InvalidPathError, "invalid path for static asset", fn ->
        call(conn(:get, "/public/fixtures/%2E%2E/fixtures/static/file.txt"))
      end

    assert Plug.Exception.status(exception) == 400

    exception =
      assert_raise Plug.Static.InvalidPathError, "invalid path for static asset", fn ->
        call(conn(:get, "/public/c:\\foo.txt"))
      end

    assert Plug.Exception.status(exception) == 400

    exception =
      assert_raise Plug.Static.InvalidPathError, "invalid path for static asset", fn ->
        call(conn(:get, "/public/sample.txt%00.html"))
      end

    assert Plug.Exception.status(exception) == 400

    exception =
      assert_raise Plug.Static.InvalidPathError, "invalid path for static asset", fn ->
        call(conn(:get, "/public/sample.txt\0.html"))
      end

    assert Plug.Exception.status(exception) == 400
  end

  test "serves gzipped file" do
    conn =
      conn(:get, "/public/fixtures/static.txt", [])
      |> put_req_header("accept-encoding", "gzip")
      |> call

    assert conn.status == 200
    assert conn.resp_body == "GZIPPED HELLO"
    assert get_resp_header(conn, "content-encoding") == ["gzip"]
    assert get_resp_header(conn, "vary") == ["Accept-Encoding"]
    assert get_resp_header(conn, "x-custom") == ["x-value"]

    conn =
      conn(:get, "/public/fixtures/static.txt", [])
      |> put_req_header("accept-encoding", "*")
      |> put_resp_header("vary", "Whatever")
      |> call

    assert conn.status == 200
    assert conn.resp_body == "GZIPPED HELLO"
    assert get_resp_header(conn, "content-encoding") == ["gzip"]
    assert get_resp_header(conn, "vary") == ["Accept-Encoding", "Whatever"]
    assert get_resp_header(conn, "x-custom") == ["x-value"]
  end

  test "only serves gzipped file if available" do
    conn =
      conn(:get, "/public/fixtures/static%20with%20spaces.txt", [])
      |> put_req_header("accept-encoding", "gzip")
      |> call

    assert conn.status == 200
    assert conn.resp_body == "SPACES"
    assert get_resp_header(conn, "content-encoding") != ["gzip"]
    assert get_resp_header(conn, "vary") == ["Accept-Encoding"]
  end

  test "raises an exception if :from isn't a binary or an atom" do
    assert_raise ArgumentError, fn ->
      defmodule ExceptionPlug do
        use Plug.Builder
        plug Plug.Static, from: 42, at: "foo"
      end
    end
  end

  describe "range request" do
    test "serves entire file if range is 0-" do
      conn =
        conn(:get, "/public/fixtures/static.txt", [])
        |> put_req_header("range", "bytes=0-")
        |> call()

      assert conn.status == 200
      assert conn.resp_body == "HELLO"
      assert get_resp_header(conn, "content-type") == ["text/plain"]
    end

    test "serves requested range of file starting from byte 0" do
      conn =
        conn(:get, "/public/fixtures/static.txt", [])
        |> put_req_header("range", "bytes=0-1")
        |> call()

      assert conn.status == 206
      assert conn.resp_body == "HE"
      assert get_resp_header(conn, "content-type") == ["text/plain"]
      assert get_resp_header(conn, "accept-ranges") == ["bytes"]
      assert get_resp_header(conn, "content-range") == ["bytes 0-1/5"]
    end

    test "serves entire file if range contains non-integers" do
      conn =
        conn(:get, "/public/fixtures/static.txt", [])
        |> put_req_header("range", "bytes=00-FF")
        |> call()

      assert conn.status == 200
      assert conn.resp_body == "HELLO"
      assert get_resp_header(conn, "content-type") == ["text/plain"]
      assert get_resp_header(conn, "accept-ranges") == ["bytes"]
    end

    test "serves the file with a custom content type" do
      conn =
        conn(:get, "/public/fixtures/manifest-file", [])
        |> put_req_header("range", "bytes=-1")
        |> call()

      assert conn.status == 206
      assert conn.resp_body == "]"
      assert get_resp_header(conn, "content-type") == ["application/vnd.manifest+json"]
      assert get_resp_header(conn, "accept-ranges") == ["bytes"]
      assert get_resp_header(conn, "content-range") == ["bytes 1-1/2"]
    end

    test "serves tail of file if range is -n" do
      conn =
        conn(:get, "/public/fixtures/static.txt", [])
        |> put_req_header("range", "bytes=-3")
        |> call()

      assert conn.status == 206
      assert conn.resp_body == "LLO"
      assert get_resp_header(conn, "content-type") == ["text/plain"]
      assert get_resp_header(conn, "accept-ranges") == ["bytes"]
      assert get_resp_header(conn, "content-range") == ["bytes 2-4/5"]
    end

    test "serves tail of file if range end greater than file length" do
      conn =
        conn(:get, "/public/fixtures/static.txt", [])
        |> put_req_header("range", "bytes=4-1024")
        |> call()

      assert conn.status == 206
      assert conn.resp_body == "O"
      assert get_resp_header(conn, "content-type") == ["text/plain"]
      assert get_resp_header(conn, "accept-ranges") == ["bytes"]
      assert get_resp_header(conn, "content-range") == ["bytes 4-4/5"]
    end

    test "returns entire file if range does not contain either start or end" do
      conn =
        conn(:get, "/public/fixtures/static.txt", [])
        |> put_req_header("range", "bytes=-")
        |> call()

      assert conn.status == 200
      assert conn.resp_body == "HELLO"
      assert get_resp_header(conn, "content-type") == ["text/plain"]
    end

    test "returns entire file if range contains non-integers" do
      conn =
        conn(:get, "/public/fixtures/static.txt", [])
        |> put_req_header("range", "bytes=nope")
        |> call()

      assert conn.status == 200
      assert conn.resp_body == "HELLO"
      assert get_resp_header(conn, "content-type") == ["text/plain"]
    end

    test "returns entire file if range is missing =" do
      conn =
        conn(:get, "/public/fixtures/static.txt", [])
        |> put_req_header("range", "bytes")
        |> call()

      assert conn.status == 200
      assert conn.resp_body == "HELLO"
      assert get_resp_header(conn, "content-type") == ["text/plain"]
    end

    test "returns entire file if range contains multiple byte ranges" do
      # Multiple byte ranges are not supported by Plug.Static at this time.

      conn =
        conn(:get, "/public/fixtures/static.txt", [])
        |> put_req_header("range", "bytes=0-1,3-4")
        |> call()

      assert conn.status == 200
      assert conn.resp_body == "HELLO"
      assert get_resp_header(conn, "content-type") == ["text/plain"]
    end

    test "performs etag negotiation" do
      conn =
        conn(:get, "/public/fixtures/static.txt")
        |> put_req_header("range", "bytes=0-1")
        |> call()

      assert conn.status == 206
      assert conn.resp_body == "HE"
      assert get_resp_header(conn, "content-type") == ["text/plain"]
      assert get_resp_header(conn, "accept-ranges") == ["bytes"]
      assert get_resp_header(conn, "content-range") == ["bytes 0-1/5"]

      assert [etag] = get_resp_header(conn, "etag")
      assert get_resp_header(conn, "cache-control") == ["public"]

      conn =
        conn(:get, "/public/fixtures/static.txt", nil)
        |> put_req_header("range", "bytes=0-1")
        |> put_req_header("if-none-match", etag)
        |> call()

      assert conn.status == 304
      assert conn.resp_body == ""
      assert get_resp_header(conn, "cache-control") == ["public"]
      assert get_resp_header(conn, "x-custom") == []
      assert get_resp_header(conn, "vary") == ["Accept-Encoding"]

      assert get_resp_header(conn, "content-type") == []
      assert get_resp_header(conn, "content-encoding") == []
      assert get_resp_header(conn, "etag") == [etag]
    end

    test "performs etag negotiation with user defined etag generation" do
      opts = [
        at: "/public",
        from: Path.expand("..", __DIR__),
        etag_generation: {EtagGenerator, :generate, ["x", "y"]}
      ]

      conn =
        conn(:get, "/public/fixtures/static.txt")
        |> put_req_header("range", "bytes=0-1")
        |> Plug.Static.call(Plug.Static.init(opts))

      assert conn.status == 206
      assert conn.resp_body == "HE"
      assert get_resp_header(conn, "content-type") == ["text/plain"]
      assert get_resp_header(conn, "accept-ranges") == ["bytes"]
      assert get_resp_header(conn, "content-range") == ["bytes 0-1/5"]
      assert [etag] = get_resp_header(conn, "etag")

      assert etag ==
               EtagGenerator.generate(Path.expand("../fixtures/static.txt", __DIR__), "x", "y")

      assert get_resp_header(conn, "cache-control") == ["public"]

      conn =
        conn(:get, "/public/fixtures/static.txt", nil)
        |> put_req_header("range", "bytes=0-1")
        |> put_req_header("if-none-match", etag)
        |> Plug.Static.call(Plug.Static.init(opts))

      assert conn.status == 304
      assert conn.resp_body == ""
      assert get_resp_header(conn, "cache-control") == ["public"]
      assert get_resp_header(conn, "content-type") == []
      assert get_resp_header(conn, "content-encoding") == []
      assert get_resp_header(conn, "etag") == [etag]
    end

    test "sets the cache-control_for_vsn_requests when there's a query string" do
      conn =
        conn(:get, "/public/fixtures/static.txt?vsn=bar")
        |> put_req_header("range", "bytes=0-1")
        |> call()

      assert conn.status == 206
      assert conn.resp_body == "HE"
      assert get_resp_header(conn, "content-type") == ["text/plain"]
      assert get_resp_header(conn, "accept-ranges") == ["bytes"]
      assert get_resp_header(conn, "content-range") == ["bytes 0-1/5"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000"]
      assert get_resp_header(conn, "etag") == []
      assert get_resp_header(conn, "x-custom") == ["x-value"]
    end

    test "doesn't set cache control headers" do
      opts = [
        at: "/public",
        from: Path.expand("..", __DIR__),
        cache_control_for_vsn_requests: nil,
        cache_control_for_etags: nil,
        headers: %{"x-custom" => "x-value"}
      ]

      conn =
        conn(:get, "/public/fixtures/static.txt")
        |> put_req_header("range", "bytes=0-1")
        |> Plug.Static.call(Plug.Static.init(opts))

      assert conn.status == 206
      assert conn.resp_body == "HE"
      assert get_resp_header(conn, "accept-ranges") == ["bytes"]
      assert get_resp_header(conn, "content-range") == ["bytes 0-1/5"]
      assert get_resp_header(conn, "cache-control") == ["max-age=0, private, must-revalidate"]
      assert get_resp_header(conn, "etag") == []
      assert get_resp_header(conn, "x-custom") == ["x-value"]
    end
  end

  defmodule FilterPlug do
    use Plug.Builder

    plug Plug.Static,
      at: "/",
      from: Path.expand("../fixtures", __DIR__),
      only: ~w(ssl static.txt)

    plug Plug.Static,
      at: "/",
      from: Path.expand("../fixtures", __DIR__),
      only_matching: ~w(file)

    plug :passthrough

    defp passthrough(conn, _), do: Plug.Conn.send_resp(conn, 404, "Passthrough")
  end

  test "serves only allowed files" do
    conn = FilterPlug.call(conn(:get, "/static.txt"), [])
    assert conn.status == 200

    conn = FilterPlug.call(conn(:get, "/ssl/server.cer"), [])
    assert conn.status == 200

    conn = FilterPlug.call(conn(:get, "/"), [])
    assert conn.status == 404

    conn = FilterPlug.call(conn(:get, "/static/file.txt"), [])
    assert conn.status == 404

    conn = FilterPlug.call(conn(:get, "/file-deadbeef.txt"), [])
    assert conn.status == 200
  end

  defmodule HeaderGenerator do
    def generate(_conn, header) do
      [header]
    end
  end

  test "MFA headers" do
    opts = [
      at: "/public",
      from: Path.expand("..", __DIR__),
      headers: {HeaderGenerator, :generate, [{"x-custom", "x-value"}]}
    ]

    conn = Plug.Static.call(conn(:get, "/public/fixtures/static.txt"), Plug.Static.init(opts))

    assert conn.status == 200
    assert get_resp_header(conn, "x-custom") == ["x-value"]
  end

  test "MFA from" do
    opts = [
      at: "/public",
      from: {Path, :expand, ["..", __DIR__]}
    ]

    conn =
      conn(:get, "/public/fixtures/static.txt")
      |> Plug.Static.call(Plug.Static.init(opts))

    assert conn.status == 200
  end
end
