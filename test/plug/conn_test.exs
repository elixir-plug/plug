defmodule Plug.ConnTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Plug.Conn
  alias Plug.ProcessStore

  test "test adapter builds on connection" do
    conn = Plug.Adapters.Test.Conn.conn(%Plug.Conn{private: %{hello: :world}}, :post, "/hello", nil)
    assert conn.method == "POST"
    assert conn.path_info == ["hello"]
    assert conn.private.hello == :world
  end

  test "test adapter stores body in process before sending" do
    # The order of the lines below matters since we are testing if sent_body/1
    # is returning the correct body even if they have the same owner process
    conn = send_resp(conn(:get, "/foo"), 200, "HELLO")
    another_conn = send_resp(conn(:get, "/foo"), 404, "TEST")

    {status, _headers, body} = sent_resp(another_conn)
    assert status == 404
    assert body == "TEST"

    {status, _headers, body} = sent_resp(conn)
    assert status == 200
    assert body == "HELLO"
  end

  test "twice sending a response" do
    conn = conn(:get, "/foo")
    send_resp(conn, 204, "")
    send_resp(conn, 200, "HELLO")

    assert_raise RuntimeError, ~r/sent more than once/, fn ->
      sent_resp(conn)
    end
  end

  test "inspect/2" do
    assert inspect(conn(:get, "/")) =~ "{Plug.Adapters.Test.Conn, :...}"
    refute inspect(conn(:get, "/"), limit: :infinity) =~ "{Plug.Adapters.Test.Conn, :...}"
  end

  test "assign/3" do
    conn = conn(:get, "/")
    assert conn.assigns[:hello] == nil
    conn = assign(conn, :hello, :world)
    assert conn.assigns[:hello] == :world
  end

  test "async_assign/3 and await_assign/3" do
    conn = conn(:get, "/")
    assert conn.assigns[:hello] == nil
    conn = async_assign(conn, :hello, fn -> :world end)
    conn = await_assign(conn, :hello)
    assert conn.assigns[:hello] == :world
  end

  test "put_status/2" do
    conn = conn(:get, "/")
    assert put_status(conn, nil).status == nil
    assert put_status(conn, 200).status == 200
    assert put_status(conn, :ok).status == 200
  end

  test "put_status/2 raises when the connection had already been sent" do
    conn = send_resp(conn(:get, "/"), 200, "foo")

    assert_raise Plug.Conn.AlreadySentError, fn ->
      put_status(conn, 200)
    end

    assert_raise Plug.Conn.AlreadySentError, fn ->
      put_status(conn, nil)
    end
  end

  test "put_private/3" do
    conn = conn(:get, "/")
    assert conn.private[:hello] == nil
    conn = put_private(conn, :hello, :world)
    assert conn.private[:hello] == :world
  end

  test "scheme, host and port fields" do
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

  test "peer and remote_ip fields" do
    conn = conn(:get, "/")
    assert conn.peer == {{127, 0, 0, 1}, 111_317}
    assert conn.remote_ip == {127, 0, 0, 1}
  end

  test "path_info" do
    assert conn(:get, "/foo/bar").path_info == ~w(foo bar)s
    assert conn(:get, "/foo/bar/").path_info == ~w(foo bar)s
    assert conn(:get, "/foo//bar").path_info == ~w(foo bar)s
  end

  test "query_string" do
    assert conn(:get, "/").query_string == ""
    assert conn(:get, "/foo?barbat").query_string == "barbat"
    assert conn(:get, "/foo/bar?bar=bat").query_string == "bar=bat"
  end

  test "request_path" do
    assert conn(:get, "/").request_path == "/"
    assert conn(:get, "/foo?barbat").request_path == "/foo"
    assert conn(:get, "/foo/bar?bar=bat").request_path == "/foo/bar"
    assert conn(:get, "/foo/bar/?bar=bat").request_path == "/foo/bar/"
    assert conn(:get, "/foo//bar").request_path == "/foo//bar"
    assert conn(:get, "/foo//bar//").request_path == "/foo//bar//"
  end

  test "status, resp_headers and resp_body" do
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
    assert conn.status == 200
    assert conn.resp_body == "HELLO"

    conn = resp(conn, :not_found, "WORLD")
    assert conn.state == :set
    assert conn.status == 404
    assert conn.resp_body == "WORLD"
  end

  test "resp/3 raises when connection was already sent" do
    conn = send_resp(conn(:head, "/foo"), 200, "HELLO")
    assert_raise Plug.Conn.AlreadySentError, fn ->
      resp(conn, 200, "OTHER")
    end
  end

  test "resp/3 raises when body is nil" do
    conn = conn(:head, "/foo")
    assert_raise ArgumentError, fn ->
      resp(conn, 200, nil)
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

  test "send_resp/3 sends owner a message" do
    refute_received {:plug_conn, :sent}
    send_resp(conn(:get, "/foo"), 200, "HELLO")
    assert_received {:plug_conn, :sent}
    resp(conn(:get, "/foo"), 200, "HELLO")
    refute_received {:plug_conn, :sent}
  end

  test "send_resp/3 does not send on head" do
    conn = send_resp(conn(:head, "/foo"), 200, "HELLO")
    assert conn.resp_body == ""
  end

  test "send_resp/3 raises when connection was already sent" do
    conn = send_resp(conn(:head, "/foo"), 200, "HELLO")
    assert_raise Plug.Conn.AlreadySentError, fn ->
      send_resp(conn, 200, "OTHER")
    end
  end

  test "send_resp/3 allows for iolist in the resp body" do
    refute_received {:plug_conn, :sent}
    conn = send_resp(conn(:get, "/foo"), 200, ["this ", ["is", " nested"]])
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

  test "send_resp/1 raises if the connection was unset" do
    conn = conn(:get, "/goo")
    assert_raise ArgumentError, fn ->
      send_resp(conn)
    end
  end

  test "send_resp/1 raises if the connection was already sent" do
    conn = send_resp(conn(:get, "/boo") , 200, "ok")
    assert_raise Plug.Conn.AlreadySentError, fn ->
      send_resp(conn)
    end
  end

  test "send_file/3" do
    conn = send_file(conn(:get, "/foo"), 200, __ENV__.file)
    assert conn.status == 200
    assert conn.resp_body =~ "send_file/3"
    assert conn.state == :sent
  end

  test "send_file/3 raises on null-byte" do
    assert_raise ArgumentError, fn ->
      send_file(conn(:get, "/foo"), 200, "foo.md\0.html")
    end
  end

  test "send_file/3 sends self a message" do
    refute_received {:plug_conn, :sent}
    send_file(conn(:get, "/foo"), 200, __ENV__.file)
    assert_received {:plug_conn, :sent}
  end

  test "send_file/3 does not send on head" do
    conn = send_file(conn(:head, "/foo"), 200, __ENV__.file)
    assert conn.resp_body == ""
  end

  test "send_file/3 raises when connection was already sent" do
    conn = send_file(conn(:head, "/foo"), 200, __ENV__.file)
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
    :rand.seed(:exs64)
    offset = round(:rand.uniform() * size)
    conn = send_file(conn(:get, "/foo"), 206, __ENV__.file, offset)
    assert conn.status == 206
    assert conn.state == :sent
    assert byte_size(conn.resp_body) == (size - offset)
  end

  test "send_file/5 limits on offset and length" do
    %File.Stat{type: :regular, size: size} = File.stat!(__ENV__.file)
    :rand.seed(:exs64)
    offset = round(:rand.uniform() * size)
    length = round((size - offset) * 0.25)
    conn = send_file(conn(:get, "/foo"), 206, __ENV__.file, offset, length)
    assert conn.status == 206
    assert conn.state == :sent
    assert byte_size(conn.resp_body) == length
  end

  test "send_chunked/3" do
    conn = send_chunked(conn(:get, "/foo"), 200)
    assert conn.status == 200
    assert conn.resp_body == ""
    {:ok, conn} = chunk(conn, "HELLO\n")
    assert conn.resp_body == "HELLO\n"
    {:ok, conn} = chunk(conn, ["WORLD", ["\n"]])
    assert conn.resp_body == "HELLO\nWORLD\n"
  end

  test "send_chunked/3 with collectable" do
    conn = send_chunked(conn(:get, "/foo"), 200)
    conn = Enum.into(~w(hello world), conn)
    assert conn.resp_body == "helloworld"
  end

  test "send_chunked/3 sends self a message" do
    refute_received {:plug_conn, :sent}
    send_chunked(conn(:get, "/foo"), 200)
    assert_received {:plug_conn, :sent}
  end

  test "send_chunked/3 does not send on head" do
    {:ok, conn} = conn(:head, "/foo") |> send_chunked(200) |> chunk("HELLO")
    assert conn.resp_body == ""
  end

  test "send_chunked/3 raises when connection was already sent" do
    conn = send_chunked(conn(:head, "/foo"), 200)
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

  test "chunk/2 raises if send_chunked/3 hasn't been called yet" do
    conn = conn(:get, "/")
    assert_raise ArgumentError, fn ->
      chunk(conn, "foobar")
    end
  end

  test "put_resp_header/3" do
    conn1 = put_resp_header(conn(:head, "/foo"), "x-foo", "bar")
    assert get_resp_header(conn1, "x-foo") == ["bar"]
    conn2 = put_resp_header(conn1, "x-foo", "baz")
    assert get_resp_header(conn2, "x-foo") == ["baz"]
    assert length(conn1.resp_headers) ==
           length(conn2.resp_headers)
  end

  test "put_resp_header/3 raises when the conn was already been sent" do
    conn = send_resp(conn(:get, "/foo"), 200, "ok")
    assert_raise Plug.Conn.AlreadySentError, fn ->
      put_resp_header(conn, "x-foo", "bar")
    end
  end

  test "put_resp_header/3 raises when invalid header key given" do
    conn = conn(:get, "/foo")
    assert_raise Plug.Conn.InvalidHeaderError, ~S[header key is not lowercase: "X-Foo"], fn ->
      put_resp_header(conn, "X-Foo", "bar")
    end
  end

  test "put_resp_header/3 raises when invalid header value given" do
    assert_raise Plug.Conn.InvalidHeaderError, ~S[header value contains control feed (\r) or newline (\n): "value\rBAR"], fn ->
      put_resp_header(conn(:get, "foo"), "x-sample", "value\rBAR")
    end

    assert_raise Plug.Conn.InvalidHeaderError, ~S[header value contains control feed (\r) or newline (\n): "value\n\nBAR"], fn ->
      put_resp_header(conn(:get, "foo"), "x-sample", "value\n\nBAR")
    end
  end

  test "merge_resp_headers/3" do
    conn1 = merge_resp_headers(conn(:head, "/foo"), %{"x-foo" => "bar", "x-bar" => "baz"})
    assert get_resp_header(conn1, "x-foo") == ["bar"]
    assert get_resp_header(conn1, "x-bar") == ["baz"]
    conn2 = merge_resp_headers(conn1, %{"x-foo" => "new"})
    assert get_resp_header(conn2, "x-foo") == ["new"]
    assert get_resp_header(conn2, "x-bar") == ["baz"]
    assert length(conn1.resp_headers) ==
           length(conn2.resp_headers)
  end

  test "delete_resp_header/2" do
    conn = put_resp_header(conn(:head, "/foo"), "x-foo", "bar")
    assert get_resp_header(conn, "x-foo") == ["bar"]
    conn = delete_resp_header(conn, "x-foo")
    assert get_resp_header(conn, "x-foo") == []
  end

  test "delete_resp_header/2 raises when the conn was already been sent" do
    conn = send_resp(conn(:head, "/foo"), 200, "ok")
    assert_raise Plug.Conn.AlreadySentError, fn ->
      delete_resp_header(conn, "x-foo")
    end
  end

  test "update_resp_header/4" do
    conn1 = put_resp_header(conn(:head, "/foo"), "x-foo", "bar")
    conn2 = update_resp_header(conn1, "x-foo", "bong", &(&1 <> ", baz"))
    assert get_resp_header(conn2, "x-foo") == ["bar, baz"]
    assert length(conn1.resp_headers) == length(conn2.resp_headers)

    conn1 = conn(:head, "/foo")
    conn2 = update_resp_header(conn1, "x-foo", "bong", &(&1 <> ", baz"))
    assert get_resp_header(conn2, "x-foo") == ["bong"]

    conn1 = %{conn(:head, "/foo") | resp_headers:
      [{"x-foo", "foo"}, {"x-foo", "bar"}]}
    conn2 = update_resp_header(conn1, "x-foo", "in", &String.upcase/1)
    assert get_resp_header(conn2, "x-foo") == ["FOO", "bar"]
  end

  test "update_resp_header/4 raises when the conn was already been sent" do
    conn = send_resp(conn(:head, "/foo"), 200, "ok")
    assert_raise Plug.Conn.AlreadySentError, fn ->
      update_resp_header(conn, "x-foo", "init", &(&1))
    end
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
    conn = resp(conn(:get, "/foo"), 200, "HELLO")
    assert conn.status == 200
    assert conn.resp_body == "HELLO"

    conn = send_resp(conn)
    assert conn.status == 200
    assert conn.resp_body == "HELLO"
  end

  test "get_req_header/2, put_req_header/3 and delete_req_header/2" do
    conn = conn(:get, "/")
    assert get_req_header(conn, "foo") == []

    conn = put_req_header(conn, "foo", "bar")
    assert get_req_header(conn, "foo") == ["bar"]

    conn = put_req_header(conn, "foo", "baz")
    assert get_req_header(conn, "foo") == ["baz"]

    conn = delete_req_header(conn, "foo")
    assert get_req_header(conn, "foo") == []
  end

  test "put_req_header/3" do
    conn1 = put_req_header(conn(:head, "/foo"), "x-foo", "bar")
    assert get_req_header(conn1, "x-foo") == ["bar"]
    conn2 = put_req_header(conn1, "x-foo", "baz")
    assert get_req_header(conn2, "x-foo") == ["baz"]
    assert length(conn1.req_headers) ==
           length(conn2.req_headers)
  end

  test "put_req_header/3 raises when the conn was already been sent" do
    conn = send_resp(conn(:get, "/foo"), 200, "ok")
    assert_raise Plug.Conn.AlreadySentError, fn ->
      put_req_header(conn, "x-foo", "bar")
    end
  end

  test "put_req_header/3 raises when invalid header key given" do
    conn = conn(:get, "/foo")
    assert_raise Plug.Conn.InvalidHeaderError, ~S[header key is not lowercase: "X-Foo"], fn ->
      put_req_header(conn, "X-Foo", "bar")
    end
  end

  test "delete_req_header/2" do
    conn = put_req_header(conn(:head, "/foo"), "x-foo", "bar")
    assert get_req_header(conn, "x-foo") == ["bar"]
    conn = delete_req_header(conn, "x-foo")
    assert get_req_header(conn, "x-foo") == []
  end

  test "delete_req_header/2 raises when the conn was already been sent" do
    conn = send_resp(conn(:head, "/foo"), 200, "ok")
    assert_raise Plug.Conn.AlreadySentError, fn ->
      delete_req_header(conn, "x-foo")
    end
  end

  test "update_req_header/4" do
    conn1 = put_req_header(conn(:head, "/foo"), "x-foo", "bar")
    conn2 = update_req_header(conn1, "x-foo", "bong", &(&1 <> ", baz"))
    assert get_req_header(conn2, "x-foo") == ["bar, baz"]
    assert length(conn1.req_headers) == length(conn2.req_headers)

    conn1 = conn(:head, "/foo")
    conn2 = update_req_header(conn1, "x-foo", "bong", &(&1 <> ", baz"))
    assert get_req_header(conn2, "x-foo") == ["bong"]

    conn1 = %{conn(:head, "/foo") | req_headers:
      [{"x-foo", "foo"}, {"x-foo", "bar"}]}
    conn2 = update_req_header(conn1, "x-foo", "in", &String.upcase/1)
    assert get_req_header(conn2, "x-foo") == ["FOO", "bar"]
  end

  test "update_req_header/4 raises when the conn was already been sent" do
    conn = send_resp(conn(:head, "/foo"), 200, "ok")
    assert_raise Plug.Conn.AlreadySentError, fn ->
      update_req_header(conn, "x-foo", "init", &(&1))
    end
  end

  test "read_body/1" do
    body = :binary.copy("abcdefghij", 1000)
    conn = put_req_header(conn(:post, "/foo", body), "content-type", "text/plain")
    assert {:ok, ^body, conn} = read_body(conn)
    assert {:ok, "", _} = read_body(conn)
  end

  test "read_body/2 partial retrieval" do
    body = :binary.copy("abcdefghij", 100)
    conn = put_req_header(conn(:post, "/foo", body), "content-type", "text/plain")
    assert {:more, _, _} = read_body(conn, length: 100)
  end

  test "query_params/1 and fetch_query_params/1" do
    conn = conn(:get, "/foo?a=b&c=d")
    assert conn.query_params == %Plug.Conn.Unfetched{aspect: :query_params}
    conn = fetch_query_params(conn)
    assert conn.query_params == %{"a" => "b", "c" => "d"}

    conn = fetch_query_params(conn(:get, "/foo"), []) # Pluggable
    assert conn.query_params == %{}
  end

  test "query_params/1, params/1 and fetch_query_params/1" do
    conn = conn(:get, "/foo?a=b&c=d")
    assert conn.params == %Plug.Conn.Unfetched{aspect: :params}
    conn = fetch_query_params(conn)
    assert conn.params == %{"a" => "b", "c" => "d"}

    conn = conn(:get, "/foo?a=b&c=d")
    conn = put_in conn.params, %{"a" => "z"}
    conn = fetch_query_params(conn)
    assert conn.params == %{"a" => "z", "c" => "d"}
  end

  test "fetch_query_params/1 with invalid utf-8" do
    conn = conn(:get, "/foo?a=" <> <<139>>)
    assert_raise Plug.Conn.InvalidQueryError,
                 "invalid UTF-8 on query string, got byte 139", fn ->
      fetch_query_params(conn)
    end
  end

  test "req_cookies/1 && fetch_cookies/1" do
    conn = put_req_header(conn(:get, "/"), "cookie", "foo=bar; baz=bat")
    assert conn.req_cookies == %Plug.Conn.Unfetched{aspect: :cookies}
    conn = fetch_cookies(conn)
    assert conn.req_cookies == %{"foo" => "bar", "baz" => "bat"}

    conn = fetch_cookies(conn(:get, "/foo"), []) # Pluggable
    assert conn.req_cookies == %{}
  end

  test "put_resp_cookie/4 and delete_resp_cookie/3" do
    conn = send_resp(conn(:get, "/"), 200, "ok")
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

  test "put_resp_cookie/4 raises when over 4096 bytes" do
    assert_raise Plug.Conn.CookieOverflowError, fn ->
      conn(:get, "/")
      |> put_resp_cookie("foo", String.duplicate("a", 4095))
      |> send_resp(200, "OK")
    end
  end

  test "put_resp_cookie/4 is secure on https" do
    conn = conn(:get, "https://example.com/")
           |> put_resp_cookie("foo", "baz", path: "/baz")
           |> send_resp(200, "ok")
    assert conn.resp_cookies["foo"] ==
           %{value: "baz", path: "/baz", secure: true}

    conn = conn(:get, "https://example.com/")
           |> put_resp_cookie("foo", "baz", path: "/baz", secure: false)
           |> send_resp(200, "ok")
    assert conn.resp_cookies["foo"] ==
           %{value: "baz", path: "/baz", secure: false}
  end

  test "put_req_cookie/3 and delete_req_cookie/2" do
    conn = conn(:get, "/")
    assert get_req_header(conn, "cookie") == []

    conn = put_req_cookie(conn, "foo", "bar")
    assert get_req_header(conn, "cookie") == ["foo=bar"]

    conn = delete_req_cookie(conn, "foo")
    assert get_req_header(conn, "cookie") == []

    conn = conn |> put_req_cookie("foo", "bar") |> put_req_cookie("baz", "bat") |> fetch_cookies
    assert conn.req_cookies["foo"] == "bar"
    assert conn.req_cookies["baz"] == "bat"

    assert_raise ArgumentError, fn ->
      put_req_cookie(conn, "foo", "bar")
    end
  end

  test "put_resp_cookie/4 and delete_resp_cookie/3 raise when the connection was already sent" do
    conn = send_resp(conn(:get, "/foo"), 200, "ok")
    assert_raise Plug.Conn.AlreadySentError, fn ->
      put_resp_cookie(conn, "foo", "bar")
    end
    assert_raise Plug.Conn.AlreadySentError, fn ->
      delete_resp_cookie(conn, "foo")
    end
  end

  test "recycle_cookies/2" do
    conn = conn(:get, "/foo", a: "b", c: [%{d: "e"}, "f"])
           |> put_req_cookie("req_cookie", "req_cookie")
           |> put_req_cookie("del_cookie", "del_cookie")
           |> put_req_cookie("over_cookie", "pre_cookie")
           |> put_resp_cookie("over_cookie", "pos_cookie")
           |> put_resp_cookie("resp_cookie", "resp_cookie")
           |> delete_resp_cookie("del_cookie")

    conn = conn(:get, "/") |> recycle_cookies(conn) |> fetch_cookies()
    assert conn.cookies == %{"req_cookie"  => "req_cookie",
                             "over_cookie" => "pos_cookie",
                             "resp_cookie" => "resp_cookie"}
  end

  test "cookies/1 loaded early" do
    conn = put_req_cookie(conn(:get, "/"), "foo", "bar")
    assert conn.cookies == %Plug.Conn.Unfetched{aspect: :cookies}

    conn = fetch_cookies(conn)
    assert conn.cookies["foo"] == "bar"

    conn = put_resp_cookie(conn, "bar", "baz")
    assert conn.cookies["bar"] == "baz"

    conn = put_resp_cookie(conn, "foo", "baz")
    assert conn.cookies["foo"] == "baz"

    conn = delete_resp_cookie(conn, "foo")
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

  test "fetch_session/2 returns the same conn on subsequent calls" do
    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = conn(:get, "/") |> Plug.Session.call(opts) |> fetch_session()

    assert fetch_session(conn) == conn
  end

  test "session not fetched" do
    conn = conn(:get, "/")

    assert_raise ArgumentError, "session not fetched, call fetch_session/2", fn ->
      get_session(conn, :foo)
    end

    assert_raise ArgumentError, "cannot fetch session without a configured session plug", fn ->
      fetch_session(conn)
    end

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts)

    assert_raise ArgumentError, "session not fetched, call fetch_session/2", fn ->
      get_session(conn, :foo)
    end

    conn = fetch_session(conn, []) # Pluggable
    get_session(conn, :foo)
  end

  test "get and put session" do
    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = conn(:get, "/") |> Plug.Session.call(opts) |> fetch_session()

    conn = put_session(conn, "foo", :bar)
    conn = put_session(conn, :key, 42)

    assert conn.private[:plug_session_info] == :write

    assert get_session(conn, :foo) == :bar
    assert get_session(conn, :key) == 42
    assert get_session(conn, :unknown) == nil
    assert get_session(conn, "foo") == :bar
    assert get_session(conn, "key") == 42
    assert get_session(conn, "unknown") == nil

    conn = %{conn|state: :sent}
    assert_raise Plug.Conn.AlreadySentError, fn ->
      put_session(conn, :key, 42)
    end

    conn = %{conn|state: :file}
    assert_raise Plug.Conn.AlreadySentError, fn ->
      put_session(conn, :key, 42)
    end

    conn = %{conn|state: :chunked}
    assert_raise Plug.Conn.AlreadySentError, fn ->
      put_session(conn, :key, 42)
    end
  end

  test "configure_session/2" do
    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = conn(:get, "/") |> Plug.Session.call(opts) |> fetch_session()

    conn = configure_session(conn, drop: false, renew: false)
    assert conn.private[:plug_session_info] == nil

    conn = configure_session(conn, drop: true)
    assert conn.private[:plug_session_info] == :drop

    conn = configure_session(conn, renew: true)
    assert conn.private[:plug_session_info] == :renew

    conn = put_session(conn, "foo", "bar")
    assert conn.private[:plug_session_info] == :renew

    conn = %{conn|state: :sent}
    assert_raise Plug.Conn.AlreadySentError, fn ->
      configure_session(conn, renew: true)
    end

    conn = %{conn|state: :file}
    assert_raise Plug.Conn.AlreadySentError, fn ->
      configure_session(conn, renew: true)
    end

    conn = %{conn|state: :chunked}
    assert_raise Plug.Conn.AlreadySentError, fn ->
      configure_session(conn, renew: true)
    end
  end

  test "configure_session/2 fails when there is no session" do
    conn = conn(:get, "/")
    assert_raise ArgumentError, fn ->
      configure_session(conn, drop: true)
    end
  end

  test "delete_session/2" do
    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = conn(:get, "/") |> Plug.Session.call(opts) |> fetch_session()

    conn = conn
            |> put_session("foo", "bar")
            |> put_session("baz", "boom")
            |> delete_session("baz")

    assert get_session(conn, "foo") == "bar"
    assert get_session(conn, "baz") == nil

    conn = %{conn|state: :sent}
    assert_raise Plug.Conn.AlreadySentError, fn ->
      delete_session(conn, "baz")
    end

    conn = %{conn|state: :file}
    assert_raise Plug.Conn.AlreadySentError, fn ->
      delete_session(conn, "baz")
    end

    conn = %{conn|state: :chunked}
    assert_raise Plug.Conn.AlreadySentError, fn ->
      delete_session(conn, "baz")
    end
  end

  test "clear_session/1" do
    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = conn(:get, "/") |> Plug.Session.call(opts) |> fetch_session()

    conn = conn
            |> put_session("foo", "bar")
            |> put_session("baz", "boom")
            |> clear_session

    assert get_session(conn, "foo") == nil
    assert get_session(conn, "baz") == nil
  end

  test "halt/1 updates halted to true" do
    conn = %Conn{}
    assert conn.halted == false
    conn = halt(conn)
    assert conn.halted == true
  end

  test "register_before_send/2 raises when a response has already been sent" do
    conn = send_resp(conn(:get, "/"), 200, "ok")
    assert_raise Plug.Conn.AlreadySentError, fn ->
      register_before_send(conn, fn(_) -> nil end)
    end
  end

  test "does not delegate to connections' adapter's chunk/2 when called with emtpy chunk" do
    defmodule RaisesOnEmptyChunkAdapter do
      defdelegate send_chunked(state, status, headers), to: Plug.Adapters.Test.Conn

      def chunk(_payload, ""), do: raise "the empty chunk was unexpectedly sent"
      def chunk(payload, chunk), do: Plug.Adapters.Test.Conn.chunk(payload, chunk)
    end

    conn = %Conn{
      adapter: {RaisesOnEmptyChunkAdapter, %{chunks: ""}},
      owner: self(),
      state: :unset
    }
    conn = Plug.Conn.send_chunked(conn, 200)

    assert {:ok, conn} == Plug.Conn.chunk(conn, "")
  end
end
