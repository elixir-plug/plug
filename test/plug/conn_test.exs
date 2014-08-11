defmodule Plug.ConnTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Plug.ProcessStore

  test "assign/3" do
    conn = conn(:get, "/")
    assert conn.assigns[:hello] == nil
    conn = assign(conn, :hello, :world)
    assert conn.assigns[:hello] == :world
  end

  test "assign_private/3" do
    conn = conn(:get, "/")
    assert conn.private[:hello] == nil
    conn = assign_private(conn, :hello, :world)
    assert conn.private[:hello] == :world
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
    assert conn(:get, "/foo/bar").path_info == ~w(foo bar)s
    assert conn(:get, "/foo/bar/").path_info == ~w(foo bar)s
    assert conn(:get, "/foo//bar").path_info == ~w(foo bar)s
  end

  test "query_string/1" do
    assert conn(:get, "/").query_string == ""
    assert conn(:get, "/foo?barbat").query_string == "barbat"
    assert conn(:get, "/foo/bar?bar=bat").query_string == "bar=bat"
  end

  test "status/1, resp_headers/1 and resp_body/1" do
    conn = conn(:get, "/foo")
    assert conn.status == nil
    assert conn.resp_headers == [{"cache-control", "max-age=0, private, must-revalidate"}]
    assert conn.resp_body == nil
  end

  test "resp/3" do
    conn = conn(:get, "/foo")
    assert conn.state == :unset
    conn = resp(conn, 200, "HELLO")
    assert conn.state == :set
  end

  test "resp/3 raises when connection was already sent" do
    conn = conn(:head, "/foo") |> send_resp(200, "HELLO")
    assert_raise Plug.Conn.AlreadySentError, fn ->
      resp(conn, 200, "OTHER")
    end
  end

  test "send_resp/3" do
    conn = conn(:get, "/foo")
    assert conn.state == :unset
    assert conn.resp_body == nil
    conn = send_resp(conn, 200, "HELLO")
    assert conn.status == 200
    assert conn.resp_body == "HELLO"
    assert conn.state == :sent
  end

  test "send_resp/3 sends self a message" do
    refute_received {:plug_conn, :sent}
    conn(:get, "/foo") |> send_resp(200, "HELLO")
    assert_received {:plug_conn, :sent}
  end

  test "send_resp/3 does not send on head" do
    conn = conn(:head, "/foo") |> send_resp(200, "HELLO")
    assert conn.resp_body == ""
  end

  test "send_resp/3 raises when connection was already sent" do
    conn = conn(:head, "/foo") |> send_resp(200, "HELLO")
    assert_raise Plug.Conn.AlreadySentError, fn ->
      send_resp(conn, 200, "OTHER")
    end
  end

  test "send_resp/3 allows for iolist in the resp body" do
    refute_received {:plug_conn, :sent}
    conn = conn(:get, "/foo") |> send_resp(200, ["this ", ["is", " nested"]])
    assert_received {:plug_conn, :sent}
    assert conn.resp_body == "this is nested"
  end

  test "send_resp/3 runs before_send callbacks" do
    conn = conn(:get, "/foo")
           |> register_before_send(&put_resp_header(&1, "x-body", &1.resp_body))
           |> register_before_send(&put_resp_header(&1, "x-body", "default"))
           |> send_resp(200, "body")

    assert get_resp_header(conn, "x-body") == ["body"]
  end

  test "send_resp/3 uses the before_send status and body" do
    conn = conn(:get, "/foo")
           |> register_before_send(&resp(&1, 200, "new body"))
           |> send_resp(204, "")

    assert conn.status == 200
    assert conn.resp_body == "new body"
  end

  test "send_resp/3 uses the before_send cookies" do
    conn = conn(:get, "/foo")
           |> register_before_send(&put_resp_cookie(&1, "hello", "world"))
           |> send_resp(200, "")

    assert conn.resp_cookies["hello"] == %{value: "world"}
  end

  test "send_file/3" do
    conn = conn(:get, "/foo") |> send_file(200, __ENV__.file)
    assert conn.status == 200
    assert conn.resp_body =~ "send_file/3"
    assert conn.state == :sent
  end

  test "send_file/3 sends self a message" do
    refute_received {:plug_conn, :sent}
    conn(:get, "/foo") |> send_file(200, __ENV__.file)
    assert_received {:plug_conn, :sent}
  end

  test "send_file/3 does not send on head" do
    conn = conn(:head, "/foo") |> send_file(200, __ENV__.file)
    assert conn.resp_body == ""
  end

  test "send_file/3 raises when connection was already sent" do
    conn = conn(:head, "/foo") |> send_file(200, __ENV__.file)
    assert_raise Plug.Conn.AlreadySentError, fn ->
      send_file(conn, 200, __ENV__.file)
    end
  end

  test "send_file/3 runs before_send callbacks" do
    conn = conn(:get, "/foo")
           |> register_before_send(&put_resp_header(&1, "x-body", &1.resp_body || "FILE"))
           |> send_file(200, __ENV__.file)

    assert get_resp_header(conn, "x-body") == ["FILE"]
  end

  test "send_file/5 limits on offset" do
    %File.Stat{type: :regular, size: size} = File.stat!(__ENV__.file)
    :random.seed(:erlang.now)
    offset = round(:random.uniform * size)
    conn = conn(:get, "/foo") |> send_file(206, __ENV__.file, offset)
    assert conn.status == 206
    assert conn.state == :sent
    assert byte_size(conn.resp_body) == (size - offset)
  end

  test "send_file/5 limits on offset and length" do
    %File.Stat{type: :regular, size: size} = File.stat!(__ENV__.file)
    :random.seed(:erlang.now)
    offset = round(:random.uniform * size)
    length = round((size - offset) * 0.25)
    conn = conn(:get, "/foo") |> send_file(206, __ENV__.file, offset, length)
    assert conn.status == 206
    assert conn.state == :sent
    assert byte_size(conn.resp_body) == length
  end

  test "send_chunked/3" do
    conn = conn(:get, "/foo") |> send_chunked(200)
    assert conn.status == 200
    assert conn.resp_body == ""
    {:ok, conn} = chunk(conn, "HELLO\n")
    assert conn.resp_body == "HELLO\n"
    {:ok, conn} = chunk(conn, ["WORLD", ["\n"]])
    assert conn.resp_body == "HELLO\nWORLD\n"
  end

  test "send_chunked/3 sends self a message" do
    refute_received {:plug_conn, :sent}
    conn(:get, "/foo") |> send_chunked(200)
    assert_received {:plug_conn, :sent}
  end

  test "send_chunked/3 does not send on head" do
    {:ok, conn} = conn(:head, "/foo") |> send_chunked(200) |> chunk("HELLO")
    assert conn.resp_body == ""
  end

  test "send_chunked/3 raises when connection was already sent" do
    conn = conn(:head, "/foo") |> send_chunked(200)
    assert_raise Plug.Conn.AlreadySentError, fn ->
      send_chunked(conn, 200)
    end
  end

  test "send_chunked/3 runs before_send callbacks" do
    conn = conn(:get, "/foo")
           |> register_before_send(&put_resp_header(&1, "x-body", &1.resp_body || "CHUNK"))
           |> send_chunked(200)

    assert get_resp_header(conn, "x-body") == ["CHUNK"]
  end

  test "put_resp_header/3" do
    conn1 = conn(:head, "/foo") |> put_resp_header("x-foo", "bar")
    assert get_resp_header(conn1, "x-foo") == ["bar"]
    conn2 = conn1 |> put_resp_header("x-foo", "baz")
    assert get_resp_header(conn2, "x-foo") == ["baz"]
    assert length(conn1.resp_headers) ==
           length(conn2.resp_headers)
  end

  test "delete_resp_header/3" do
    conn = conn(:head, "/foo") |> put_resp_header("x-foo", "bar")
    assert get_resp_header(conn, "x-foo") == ["bar"]
    conn = conn |> delete_resp_header("x-foo")
    assert get_resp_header(conn, "x-foo") == []
  end

  test "put_resp_content_type/3" do
    conn = conn(:head, "/foo")

    assert {"content-type", "text/html; charset=utf-8"} in
           put_resp_content_type(conn, "text/html").resp_headers

    assert {"content-type", "text/html; charset=iso"} in
           put_resp_content_type(conn, "text/html", "iso").resp_headers

    assert {"content-type", "text/html"} in
           put_resp_content_type(conn, "text/html", nil).resp_headers
  end

  test "resp/3 and send_resp/1" do
    conn = conn(:get, "/foo") |> resp(200, "HELLO")
    assert conn.status == 200
    assert conn.resp_body == "HELLO"

    conn = send_resp(conn)
    assert conn.status == 200
    assert conn.resp_body == "HELLO"
  end

  test "req_headers/1" do
    conn = conn(:get, "/foo", [], headers: [{"foo", "bar"}, {"baz", "bat"}])
    assert get_req_header(conn, "foo") == ["bar"]
    assert get_req_header(conn, "baz") == ["bat"]
  end

  test "read_body/1" do
    body = :binary.copy("abcdefghij", 1000)
    conn = conn(:post, "/foo", body, headers: [{"content-type", "text/plain"}])
    assert {:ok, ^body, conn} = read_body(conn)
    assert {:ok, "", _} = read_body(conn)
  end

  test "read_body/2 partial retrieval" do
    body = :binary.copy("abcdefghij", 100)
    conn = conn(:post, "/foo", body, headers: [{"content-type", "text/plain"}])
    assert {:more, _, _} = read_body(conn, length: 100)
  end

  test "params/1 && fetch_params/1" do
    conn = conn(:get, "/foo?a=b&c=d")
    assert conn.params == %Plug.Conn.Unfetched{aspect: :params}
    conn = fetch_params(conn)
    assert conn.params == %{"a" => "b", "c" => "d"}

    conn = conn(:get, "/foo") |> fetch_params
    assert conn.params == %{}
  end

  test "req_cookies/1 && fetch_params/1" do
    conn = conn(:get, "/") |> put_req_header("cookie", "foo=bar; baz=bat")
    assert conn.req_cookies == %Plug.Conn.Unfetched{aspect: :cookies}
    conn = fetch_cookies(conn)
    assert conn.req_cookies == %{"foo" => "bar", "baz" => "bat"}

    conn = conn(:get, "/foo") |> fetch_cookies
    assert conn.req_cookies == %{}
  end

  test "put_resp_cookie/4 and delete_resp_cookie/3" do
    conn = conn(:get, "/") |> send_resp(200, "ok")
    assert get_resp_header(conn, "set-cookie") == []

    conn = conn(:get, "/") |> put_resp_cookie("foo", "baz", path: "/baz") |> send_resp(200, "ok")
    assert conn.resp_cookies["foo"] ==
           %{value: "baz", path: "/baz"}
    assert get_resp_header(conn, "set-cookie") ==
           ["foo=baz; path=/baz; HttpOnly"]

    conn = conn(:get, "/") |> put_resp_cookie("foo", "baz") |>
           delete_resp_cookie("foo", path: "/baz") |> send_resp(200, "ok")
    assert conn.resp_cookies["foo"] ==
           %{max_age: 0, universal_time: {{1970, 1, 1}, {0, 0, 0}}, path: "/baz"}
    assert get_resp_header(conn, "set-cookie") ==
           ["foo=; path=/baz; expires=Thu, 01 Jan 1970 00:00:00 GMT; max-age=0; HttpOnly"]
  end

  test "put_req_cookie/3 and delete_req_cookie/2" do
    conn = conn(:get, "/")
    assert get_req_header(conn, "cookie") == []

    conn = conn |> put_req_cookie("foo", "bar")
    assert get_req_header(conn, "cookie") == ["foo=bar"]

    conn = conn |> delete_req_cookie("foo")
    assert get_req_header(conn, "cookie") == []

    conn = conn |> put_req_cookie("foo", "bar") |> put_req_cookie("baz", "bat") |> fetch_cookies
    assert conn.req_cookies["foo"] == "bar"
    assert conn.req_cookies["baz"] == "bat"

    assert_raise ArgumentError, fn ->
      conn |> put_req_cookie("foo", "bar")
    end
  end

  test "cookies/1 loaded early" do
    conn = conn(:get, "/") |> put_req_cookie("foo", "bar")
    assert conn.cookies == %Plug.Conn.Unfetched{aspect: :cookies}

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
    assert conn.cookies == %Plug.Conn.Unfetched{aspect: :cookies}

    conn = conn |> put_resp_cookie("foo", "baz") |> put_resp_cookie("baz", "bat") |>
           delete_resp_cookie("bar") |> fetch_cookies

    assert conn.cookies["foo"] == "baz"
    assert conn.cookies["baz"] == "bat"
    refute conn.cookies["bar"]
  end

  test "session not fetched" do
    conn = conn(:get, "/")

    assert_raise ArgumentError, "session not fetched, call fetch_session/1", fn ->
      get_session(conn, :foo)
    end

    assert_raise ArgumentError, "cannot fetch session without a configured session plug", fn ->
      conn |> fetch_session
    end

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts)

    assert_raise ArgumentError, "session not fetched, call fetch_session/1", fn ->
      get_session(conn, :foo)
    end

    conn = conn |> fetch_session

    get_session(conn, :foo)
  end

  test "get and put session" do
    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = conn(:get, "/") |> Plug.Session.call(opts) |> fetch_session()

    conn = put_session(conn, :foo, :bar)
    conn = put_session(conn, :key, 42)

    assert conn.private[:plug_session_info] == :write

    assert get_session(conn, :unknown) == nil
    assert get_session(conn, :foo) == :bar
    assert get_session(conn, :key) == 42
  end

  test "configure session" do
    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = conn(:get, "/") |> Plug.Session.call(opts) |> fetch_session()

    conn = configure_session(conn, drop: true)
    assert conn.private[:plug_session_info] == :drop

    conn = configure_session(conn, renew: true)
    assert conn.private[:plug_session_info] == :renew

    conn = put_session(conn, :foo, :bar)
    assert conn.private[:plug_session_info] == :renew
  end
end
