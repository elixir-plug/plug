defmodule Plug.SessionTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Plug.ProcessStore

  test "puts session cookie" do
    conn = conn(:get, "/") |> fetch_cookies
    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = send_resp(conn, 200, "")
    assert conn.resp_cookies == %{}

    conn = conn(:get, "/") |> fetch_cookies
    opts = Plug.Session.init(store: ProcessStore, key: "foobar", secure: true, path: "some/path")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = put_session(conn, :foo, :bar)
    conn = send_resp(conn, 200, "")
    assert %{"foobar" => %{value: _, secure: true, path: "some/path"}} = conn.resp_cookies
  end

  test "put session" do
    conn = conn(:get, "/") |> fetch_cookies
    conn = %{conn | cookies: %{"foobar" => "sid"}}

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = put_session(conn, :foo, :bar)
    send_resp(conn, 200, "")

    assert Process.get({:session, "sid"}) == %{foo: :bar}
  end

  test "get session" do
    Process.put({:session, "sid"}, %{foo: :bar})
    conn = conn(:get, "/") |> fetch_cookies
    conn = %{conn | cookies: %{"foobar" => "sid"}}

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    assert get_session(conn, :foo) == :bar
  end

  test "drop session" do
    Process.put({:session, "sid"}, %{foo: :bar})
    conn = conn(:get, "/") |> fetch_cookies
    conn = %{conn | cookies: %{"foobar" => "sid"}}

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = put_session(conn, :foo, :bar)
    conn = configure_session(conn, drop: true)
    conn = send_resp(conn, 200, "")

    assert conn.resp_cookies ==
           %{"foobar" => %{max_age: 0, universal_time: {{1970, 1, 1}, {0, 0, 0}}}}
  end

  test "drop session without cookie when there is no sid" do
    conn = conn(:get, "/") |> fetch_cookies
    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = put_session(conn, :foo, :bar)
    conn = configure_session(conn, drop: true)
    conn = send_resp(conn, 200, "")
    assert conn.resp_cookies == %{}
  end

  test "renew session" do
    Process.put({:session, "sid"}, %{foo: :bar})
    conn = conn(:get, "/") |> fetch_cookies
    conn = %{conn | cookies: %{"foobar" => "sid"}}

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = configure_session(conn, renew: true)
    conn = send_resp(conn, 200, "")

    assert %{"foobar" => %{value: _}} = conn.resp_cookies
    refute %{"foobar" => %{value: "sid"}} = conn.resp_cookies
  end

  test "reuses sid and as such does not generate new cookie" do
    Process.put({:session, "sid"}, [foo: :bar])
    conn = conn(:get, "/") |> fetch_cookies
    conn = %{conn | cookies: %{"foobar" => "sid"}}

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = send_resp(conn, 200, "")

    assert conn.resp_cookies == %{}
  end

  test "generates sid" do
    conn = conn(:get, "/") |> fetch_cookies

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = put_session(conn, :foo, :bar)
    conn = send_resp(conn, 200, "")

    assert %{value: sid} = conn.resp_cookies["foobar"]
    assert Process.get({:session, sid}) == %{foo: :bar}
  end

  test "converts store reference" do
    opts = Plug.Session.init(store: :ets, key: "foobar", table: :some_table)
    assert opts.store == Plug.Session.ETS
  end
end
