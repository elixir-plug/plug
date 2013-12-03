defmodule Plug.ConnectionTest do
  use ExUnit.Case, async: true
  use Plug.Test

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
    assert conn.resp_body == nil
  end

  test "send/3" do
    conn = conn(:get, "/foo")
    assert conn.state == :unsent
    assert conn.resp_body == nil
    conn = send(conn, 200, "HELLO")
    assert conn.status == 200
    assert conn.resp_body == "HELLO"
    assert conn.state == :sent
  end

  test "send/3 sends self a message" do
    refute_received { :plug_conn, :sent }
    conn(:get, "/foo") |> send(200, "HELLO")
    assert_received { :plug_conn, :sent }
  end

  test "send/3 does not send on head" do
    conn = conn(:head, "/foo") |> send(200, "HELLO")
    assert conn.resp_body == ""
  end

  test "send/3 raises when connection was already sent" do
    conn = conn(:head, "/foo") |> send(200, "HELLO")
    assert_raise Plug.Connection.AlreadySentError, fn ->
      send(conn, 200, "OTHER")
    end
  end

  test "send_file/3" do
    conn = conn(:get, "/foo")
    assert conn.state == :unsent
    assert conn.resp_body == nil
    conn = send_file(conn, 200, __FILE__)
    assert conn.status == 200
    assert conn.resp_body =~ "send_file/3"
    assert conn.state == :file
  end

  test "send_file/3 sends self a message" do
    refute_received { :plug_conn, :sent }
    conn(:get, "/foo") |> send_file(200, __FILE__)
    assert_received { :plug_conn, :sent }
  end

  test "send_file/3 does not send on head" do
    conn = conn(:head, "/foo") |> send_file(200, __FILE__)
    assert conn.resp_body == ""
  end

  test "send_file/3 raises when connection was already sent" do
    conn = conn(:head, "/foo") |> send_file(200, __FILE__)
    assert_raise Plug.Connection.AlreadySentError, fn ->
      send_file(conn, 200, __FILE__)
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
    assert conn.resp_body == "HELLO"
  end

  test "req_headers/1" do
    conn = conn(:get, "/foo", [], headers: [{ "foo", "bar" }, { "baz", "bat" }])
    assert conn.req_headers["foo"] == "bar"
    assert conn.req_headers["baz"] == "bat"
  end

  test "params/1 && fetch_params/1" do
    conn = conn(:get, "/foo?a=b&c=d")
    assert conn.params == Plug.Connection.Unfetched[aspect: :params]
    conn = fetch_params(conn)
    assert conn.params == [{ "a", "b" }, { "c", "d" }]

    conn = conn(:get, "/foo") |> fetch_params
    assert conn.params == []
  end

  test "req_cookies/1 && fetch_params/1" do
    conn = conn(:get, "/") |> put_req_header("cookie", "foo=bar; baz=bat")
    assert conn.req_cookies == Plug.Connection.Unfetched[aspect: :cookies]
    conn = fetch_cookies(conn)
    assert conn.req_cookies == [{ "foo", "bar" }, { "baz", "bat" }]

    conn = conn(:get, "/foo") |> fetch_cookies
    assert conn.req_cookies == []
  end

  test "put_resp_cookie/4 and delete_resp_cookie/3" do
    conn = conn(:get, "/") |> send(200, "ok")
    refute conn.resp_headers["set-cookie"]

    conn = conn(:get, "/") |> put_resp_cookie("foo", "baz", path: "/baz") |> send(200, "ok")
    assert conn.resp_cookies["foo"] ==
           [value: "baz", path: "/baz"]
    assert conn.resp_headers["set-cookie"] ==
           "foo=baz; path=/baz; HttpOnly"

    conn = conn(:get, "/") |> put_resp_cookie("foo", "baz") |>
           delete_resp_cookie("foo", path: "/baz") |> send(200, "ok")
    assert conn.resp_cookies["foo"] ==
           [max_age: 0, universal_time: {{1970, 1, 1}, {0, 0, 0}}, path: "/baz"]
    assert conn.resp_headers["set-cookie"] ==
           "foo=; path=/baz; expires=Thu, 01 Jan 1970 00:00:00 GMT; max-age=0; HttpOnly"
  end

  test "put_req_cookie/3 and delete_req_cookie/2" do
    conn = conn(:get, "/")
    refute conn.req_headers["cookie"]

    conn = conn |> put_req_cookie("foo", "bar")
    assert conn.req_headers["cookie"] == "foo=bar"

    conn = conn |> delete_req_cookie("foo")
    refute conn.req_headers["cookie"]

    conn = conn |> put_req_cookie("foo", "bar") |> put_req_cookie("baz", "bat") |> fetch_cookies
    assert conn.req_cookies["foo"] == "bar"
    assert conn.req_cookies["baz"] == "bat"

    assert_raise ArgumentError, fn ->
      conn |> put_req_cookie("foo", "bar")
    end
  end

  test "cookies/1 loaded early" do
    conn = conn(:get, "/") |> put_req_cookie("foo", "bar")
    assert conn.cookies == Plug.Connection.Unfetched[aspect: :cookies]

    conn = conn |> fetch_cookies
    assert conn.cookies["foo"] == "bar"

    conn = conn |> put_resp_cookie("bar", "baz")
    assert conn.cookies["bar"] == "baz"

    conn = conn |> put_resp_cookie("foo", "baz")
    assert conn.cookies["foo"] == "baz"

    conn = conn |> delete_resp_cookie("foo")
    refute conn.cookies["foo"]
  end

  test "cookies/1 loaded late" do
    conn = conn(:get, "/") |> put_req_cookie("foo", "bar") |> put_req_cookie("bar", "baz")
    assert conn.cookies == Plug.Connection.Unfetched[aspect: :cookies]

    conn = conn |> put_resp_cookie("foo", "baz") |> put_resp_cookie("baz", "bat") |>
           delete_resp_cookie("bar") |> fetch_cookies

    assert conn.cookies["foo"] == "baz"
    assert conn.cookies["baz"] == "bat"
    refute conn.cookies["bar"]
  end
end
