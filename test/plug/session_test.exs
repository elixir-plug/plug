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
    conn = put_session(conn, "foo", "bar")
    conn = send_resp(conn, 200, "")
    assert %{"foobar" => %{value: _, secure: true, path: "some/path"}} = conn.resp_cookies
    refute conn.resp_cookies["foobar"] |> Map.has_key?(:http_only)

    conn = conn(:get, "/") |> fetch_cookies
    opts = Plug.Session.init(store: ProcessStore, key: "unsafe_foobar", http_only: false, path: "some/path")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = put_session(conn, "foo", "bar")
    conn = send_resp(conn, 200, "")
    assert %{"unsafe_foobar" => %{value: _, http_only: false, path: "some/path"}} = conn.resp_cookies
  end

  test "put session" do
    conn = conn(:get, "/") |> fetch_cookies
    conn = %{conn | cookies: %{"foobar" => "sid"}}

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = put_session(conn, "foo", "bar")
    send_resp(conn, 200, "")

    assert Process.get({:session, "sid"}) == %{"foo" => "bar"}
  end

  test "get session" do
    Process.put({:session, "sid"}, %{"foo" => "bar"})
    conn = conn(:get, "/") |> fetch_cookies
    conn = %{conn | cookies: %{"foobar" => "sid"}}

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    assert get_session(conn, "foo") == "bar"
  end

  test "drop session" do
    Process.put({:session, "sid"}, %{"foo" => "bar"})
    conn = conn(:get, "/") |> fetch_cookies
    conn = %{conn | cookies: %{"foobar" => "sid"}}

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = put_session(conn, "foo", "bar")
    conn = configure_session(conn, drop: true)
    conn = send_resp(conn, 200, "")

    assert conn.resp_cookies ==
           %{"foobar" => %{max_age: 0, universal_time: {{1970, 1, 1}, {0, 0, 0}}}}
  end

  test "drop session without cookie when there is no sid" do
    conn = conn(:get, "/") |> fetch_cookies
    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = put_session(conn, "foo", "bar")
    conn = configure_session(conn, drop: true)
    conn = send_resp(conn, 200, "")
    assert conn.resp_cookies == %{}
  end

  test "renew session" do
    Process.put({:session, "sid"}, %{"foo" => "bar"})
    conn = conn(:get, "/") |> fetch_cookies
    conn = %{conn | cookies: %{"foobar" => "sid"}}

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = configure_session(conn, renew: true)
    conn = send_resp(conn, 200, "")

    assert match? %{"foobar" => %{value: _}}, conn.resp_cookies
    refute match? %{"foobar" => %{value: "sid"}}, conn.resp_cookies
  end

  test "ignore changes to session" do
    conn = conn(:get, "/") |> fetch_cookies
    opts = Plug.Session.init(store: ProcessStore, key: "foobar", secure: true, path: "some/path")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = configure_session(conn, ignore: true)
    conn = put_session(conn, "foo", "bar")
    conn = send_resp(conn, 200, "")

    assert conn.resp_cookies == %{}
  end

  test "reuses sid and as such does not generate new cookie" do
    Process.put({:session, "sid"}, %{"foo" => "bar"})
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
    conn = put_session(conn, "foo", "bar")
    conn = send_resp(conn, 200, "")

    assert %{value: sid} = conn.resp_cookies["foobar"]
    assert Process.get({:session, sid}) == %{"foo" => "bar"}
  end

  test "converts store reference" do
    opts = Plug.Session.init(store: :ets, key: "foobar", table: :some_table)
    assert opts.store == Plug.Session.ETS
  end

  test "init_test_session/2" do
    conn = conn(:get, "/") |> init_test_session(foo: "bar")
    assert get_session(conn, :foo) == "bar"

    conn = fetch_session(conn)
    assert get_session(conn, :foo) == "bar"

    conn = put_session(conn, :bar, "foo")
    assert get_session(conn, :bar) == "foo"

    conn = delete_session(conn, :bar)
    refute get_session(conn, :bar)

    conn = clear_session(conn)
    refute get_session(conn, :foo)
  end

  test "init_test_session/2 merges values when called after Plug.Session" do
    conn = conn(:get, "/") |> fetch_cookies

    opts = Plug.Session.init(store: ProcessStore, key: "foobar")
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = conn |> put_session(:foo, "bar") |> put_session(:bar, "foo")
    conn = init_test_session(conn, bar: "bar", other: "other")

    assert get_session(conn, :foo) == "bar"
    assert get_session(conn, :other) == "other"
    assert get_session(conn, :bar) == "bar"
  end

  test "init_test_session/2 merges values when called before Plug.Session" do
    opts = Plug.Session.init(store: ProcessStore, key: "foobar")

    conn = conn(:get, "/") |> fetch_cookies
    conn = Plug.Session.call(conn, opts) |> fetch_session
    conn = conn |> put_session(:foo, "bar") |> put_session(:bar, "foo")
    conn = send_resp(conn, 200, "")

    conn = conn(:get, "/") |> recycle_cookies(conn)
    conn = init_test_session(conn, bar: "bar", other: "other")
    conn = Plug.Session.call(conn, opts) |> fetch_session

    assert get_session(conn, :foo) == "bar"
    assert get_session(conn, :other) == "other"
    assert get_session(conn, :bar) == "bar"
  end
end
