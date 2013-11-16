defmodule Plug.ConnectionTest do
  use ExUnit.Case, async: true

  import Plug.Connection
  import Plug.Test

  test "assign/3" do
    conn = conn(:get, "/")
    assert conn.assigns[:hello] == nil
    conn = assign(conn, :hello, :world)
    assert conn.assigns[:hello] == :world
  end

  test "scheme/1, host/1 and port/1" do
    conn = conn(:get, "/")
    assert conn.scheme == :http
    assert conn.host == "www.example.com"
    assert conn.port == 80

    conn = conn(:get, "https://127.0.0.1/")
    assert conn.scheme == :https
    assert conn.host == "127.0.0.1"
    assert conn.port == 443

    conn = conn(:get, "//example.com:8080/")
    assert conn.scheme == :http
    assert conn.host == "example.com"
    assert conn.port == 8080
  end

  test "path_info/1" do
    assert conn(:get, "/foo/bar").path_info == %w(foo bar)s
    assert conn(:get, "/foo/bar/").path_info == %w(foo bar)s
    assert conn(:get, "/foo//bar").path_info == %w(foo bar)s
  end

  test "query_string/1" do
    assert conn(:get, "/").query_string == ""
    assert conn(:get, "/foo?barbat").query_string == "barbat"
    assert conn(:get, "/foo/bar?bar=bat").query_string == "bar=bat"
  end

  test "status/1, resp_headers/1 and resp_body/1" do
    conn = conn(:get, "/foo")
    assert conn.status == nil
    assert conn.resp_headers == [{ "cache-control", "max-age=0, private, must-revalidate" }]
    assert conn.resp_body == ""
  end

  test "send/3" do
    conn = conn(:get, "/foo")
    assert conn.state == :unsent
    assert sent_body(conn) == nil
    conn = send(conn, 200, "HELLO")
    assert conn.status == 200
    assert conn.resp_body == nil
    assert conn.state == :sent
    assert sent_body(conn) == "HELLO"
  end

  test "send/3 sends self a message" do
    refute_received { :plug_conn, :sent }
    conn(:get, "/foo") |> send(200, "HELLO")
    assert_received { :plug_conn, :sent }
  end

  test "send/3 does not send on head" do
    conn = conn(:head, "/foo") |> send(200, "HELLO")
    assert sent_body(conn) == ""
  end

  test "send/3 raises when connection was already sent" do
    conn = conn(:head, "/foo") |> send(200, "HELLO")
    assert_raise Plug.Connection.AlreadySentError, fn ->
      send(conn, 200, "OTHER")
    end
  end

  test "put_resp_header/3" do
    conn1 = conn(:head, "/foo") |> put_resp_header("x-foo", "bar")
    assert conn1.resp_headers["x-foo"] == "bar"
    conn2 = conn1 |> put_resp_header("x-foo", "baz")
    assert conn2.resp_headers["x-foo"] == "baz"
    assert length(conn1.resp_headers) == length(conn2.resp_headers)
  end

  test "delete_resp_header/3" do
    conn = conn(:head, "/foo") |> put_resp_header("x-foo", "bar")
    assert conn.resp_headers["x-foo"] == "bar"
    conn = conn |> delete_resp_header("x-foo")
    assert nil? conn.resp_headers["x-foo"]
  end

  test "put_resp_content_type/3" do
    conn = conn(:head, "/foo")

    assert { "content-type", "text/html; charset=utf-8" } in
           put_resp_content_type(conn, "text/html").resp_headers

    assert { "content-type", "text/html; charset=iso" } in
           put_resp_content_type(conn, "text/html", "iso").resp_headers

    assert { "content-type", "text/html" } in
           put_resp_content_type(conn, "text/html", nil).resp_headers
  end

  test "resp/3 and send/1" do
    conn = conn(:get, "/foo") |> resp(200, "HELLO")
    assert conn.status == 200
    assert conn.resp_body == "HELLO"

    conn = send(conn)
    assert conn.status == 200
    assert conn.resp_body == nil
    assert sent_body(conn) == "HELLO"
  end
end
