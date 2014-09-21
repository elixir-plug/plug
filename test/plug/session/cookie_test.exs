defmodule Plug.Session.CookieTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Plug.Session.COOKIE, as: CookieStore

  @secret_key_base String.duplicate("abcdef0123456789", 8)
  @default_opts [
    store: :cookie,
    key: "foobar",
    secret_key_base: @secret_key_base,
    encryption_salt: "encrypted cookie salt",
    signing_salt: "signing salt"
  ]

  setup do
    opts = Plug.Session.init(Keyword.merge(@default_opts, encrypt: false))
    encrypted_opts = Plug.Session.init(@default_opts)

    conn = Plug.Session.call(conn(:get, "/"), opts) |> fetch_session
    encrypted = Plug.Session.call(conn(:get, "/"), encrypted_opts) |> fetch_session

    {:ok, %{conn: conn, encrypted: encrypted}}
  end

  test "requires secret_key_base option , socket: nilto be defined" do
    assert_raise ArgumentError, ~r/cookie store expects a :secret_key_base option/, fn ->
      Plug.Session.init(Keyword.delete(@default_opts, :secret_key_base))
    end
  end

  test "requires signing_salt option to be defined" do
    assert_raise ArgumentError, ~r/expects a :signing_salt option/, fn ->
      Plug.Session.init(Keyword.delete(@default_opts, :signing_salt))
    end
  end

  test "requires the secret to be at least 64 bytes" do
    assert_raise ArgumentError, ~r/must be at least 64 bytes/, fn ->
      Plug.Session.init(Keyword.merge(@default_opts, secret_key_base: "abcdef"))
    end
  end

  test "session cookies are encoded and signed" do
    opts = CookieStore.init(Keyword.merge(@default_opts, encrypt: false))
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

  test "encrypted session cookies are encoded and signed" do
    opts = CookieStore.init(@default_opts)
    cookie = CookieStore.put(nil, %{foo: :bar}, opts)
    refute cookie == %{foo: :bar}
    assert CookieStore.get(cookie, opts) == %{foo: :bar}
  end

  test "put encrypted session cookie", %{encrypted: conn} do
    conn = put_session(conn, :foo, "bar")
    conn = send_resp(conn, 200, "")
    assert get_session(conn, :foo) == "bar"
  end

  test "get encrypted session cookie", %{encrypted: conn} do
    conn = put_session(conn, :current_user, 1)
    assert get_session(conn, :current_user) == 1
  end

  test "delete encrypted session cookie", %{encrypted: conn} do
    conn = put_session(conn, :foo, :bar)
    assert get_session(conn, :foo) == :bar
    conn = configure_session(conn, drop: true)
    conn = send_resp(conn, 200, "")

    assert conn.resp_cookies == %{}
  end

  test "converts store reference" do
    opts = Plug.Session.init(@default_opts)
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
