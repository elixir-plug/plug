defmodule Plug.StaticTest do
  use ExUnit.Case, async: true
  use Plug.Test

  defmodule MyPlug do
    use Plug.Builder

    plug Plug.Static, at: "/public", from: Path.expand("..", __DIR__), gzip: true
    plug :passthrough

    defp passthrough(conn, _) do
      Plug.Conn.send_resp(conn, 404, "Passthrough")
    end
  end

  defp call(conn) do
    MyPlug.call(conn, [])
  end

  test "serves the file" do
    conn = conn(:get, "/public/fixtures/static.txt") |> call
    assert conn.status == 200
    assert conn.resp_body == "HELLO"
    assert get_resp_header(conn, "content-type")  == ["text/plain"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000"]
  end

  test "serves the file with a urlencoded filename" do
    conn = conn(:get, "/public/fixtures/static%20with%20spaces.txt") |> call
    assert conn.status == 200
    assert conn.resp_body == "SPACES"
    assert get_resp_header(conn, "content-type")  == ["text/plain"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000"]
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
    conn = conn(:get, "/public/fixtures/../fixtures/static/file.txt") |> call
    assert conn.status    == 400
    assert conn.resp_body == "Bad request"

    conn = conn(:get, "/public/c:\\foo.txt") |> call
    assert conn.status    == 400
    assert conn.resp_body == "Bad request"
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
end
