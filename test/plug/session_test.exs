defmodule Plug.SessionTest do
  use ExUnit.Case, async: true
  use Plug.Test
  import Plug.Connection

  defmodule ProcessStore do
    @behaviour Plug.Session.Store

    def init(_opts) do
      nil
    end

    def get(sid, nil) do
      { sid, Process.get({ :session, sid }) }
    end

    def delete(sid, nil) do
      Process.delete({ :session, sid })
      :ok
    end

    def put(nil, data, nil) do
      sid = :crypto.strong_rand_bytes(96) |> :base64.encode
      put(sid, data, nil)
    end

    def put(sid, data, nil) do
      Process.put({ :session, sid }, data)
      sid
    end
  end

  test "sets session cookie" do
    conn = conn(:get, "/") |> fetch_cookies
    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = send_resp(conn, 200, "")
    assert [] = conn.resp_cookies

    conn = conn(:get, "/") |> fetch_cookies
    opts = Plug.Session.init(store: ProcessStore, key: "foobar", secure: true, path: "some/path")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = put_session(conn, :foo, :bar)
    conn = send_resp(conn, 200, "")
    assert [{ "foobar", [value: _, secure: true, path: "some/path"] }] = conn.resp_cookies
  end

  test "put session" do
    conn = conn(:get, "/") |> fetch_cookies
    conn = conn.cookies([{ "foobar", "sid" }])

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = put_session(conn, :foo, :bar)
    send_resp(conn, 200, "")

    assert Process.get({ :session, "sid" }) == [foo: :bar]
  end

  test "get session" do
    Process.put({ :session, "sid" }, [foo: :bar])
    conn = conn(:get, "/") |> fetch_cookies
    conn = conn.cookies([{ "foobar", "sid" }])

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    assert get_session(conn, :foo) == :bar
  end

  test "drop session" do
    Process.put({ :session, "sid" }, [foo: :bar])
    conn = conn(:get, "/") |> fetch_cookies
    conn = conn.cookies([{ "foobar", "sid" }])

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = put_session(conn, :foo, :bar)
    conn = configure_session(conn, drop: true)
    conn = send_resp(conn, 200, "")

    assert [] = conn.resp_cookies
  end

  test "renew session" do
    Process.put({ :session, "sid" }, [foo: :bar])
    conn = conn(:get, "/") |> fetch_cookies
    conn = conn.cookies([{ "foobar", "sid" }])

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = configure_session(conn, renew: true)
    conn = send_resp(conn, 200, "")

    assert [{ "foobar", [value: _] }] = conn.resp_cookies
    refute [{ "foobar", [value: "sid"] }] = conn.resp_cookies
  end

  test "reuses sid" do
    Process.put({ :session, "sid" }, [foo: :bar])
    conn = conn(:get, "/") |> fetch_cookies
    conn = conn.cookies([{ "foobar", "sid" }])

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = send_resp(conn, 200, "")

    assert [{ "foobar", [value: "sid"] }] = conn.resp_cookies
  end

  test "generates sid" do
    conn = conn(:get, "/") |> fetch_cookies

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = put_session(conn, :foo, :bar)
    conn = send_resp(conn, 200, "")

    assert [value: sid] = conn.resp_cookies["foobar"]
    assert Process.get({ :session, sid }) == [foo: :bar]
  end
end
