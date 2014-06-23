defmodule Plug.Session.CookieTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Plug.Session.COOKIE, as: CookieStore

  @valid_secret String.duplicate("abcdef0123456789", 8)

  setup do
    conn = conn(:get, "/")
    opts = Plug.Session.init(store: :cookie, key: "foobar", secret: @valid_secret)
    conn = Plug.Session.call(conn, opts) |> fetch_session
    {:ok, %{conn: conn}}
  end

  test "requires a secret to be defined" do
    assert_raise ArgumentError, ~r/expects a secret as option/, fn ->
      Plug.Session.init(store: :cookie, key: "foobar")
    end
  end

  test "requires the secret to be at least 64 bytes" do
    assert_raise ArgumentError, ~r/must be at least 64 bytes/, fn ->
      Plug.Session.init(store: :cookie, key: "foobar", secret: "abcdef")
    end
  end

  test "session cookies are encoded and signed" do
    opts = CookieStore.init(key: "foobar", secret: @valid_secret)
    cookie = CookieStore.put(nil, %{foo: :bar}, opts)
    refute cookie == %{foo: :bar}
    assert decode_cookie(cookie) == %{foo: :bar}
  end

  test "put session cookie", %{conn: conn} do
    conn = put_session(conn, :foo, "bar")
    conn = send_resp(conn, 200, "")
    assert get_session(conn, :foo) == "bar"
  end

  test "get session cookie", %{conn: conn} do
    conn = put_session(conn, :current_user, 1)
    assert get_session(conn, :current_user) == 1
  end

  test "delete session cookie", %{conn: conn} do
    conn = put_session(conn, :foo, :bar)
    assert get_session(conn, :foo) == :bar
    conn = configure_session(conn, drop: true)
    conn = send_resp(conn, 200, "")

    assert conn.resp_cookies == %{}
  end

  test "converts store reference" do
    opts = Plug.Session.init(store: :cookie, key: "foobar", secret: @valid_secret)
    assert opts.store == Plug.Session.COOKIE
  end

  defp decode_cookie(cookie) do
    cookie
    |> String.split("--")
    |> List.first
    |> Base.decode64!
    |> :erlang.binary_to_term
  end
end
