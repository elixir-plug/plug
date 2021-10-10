defmodule Plug.Session.CookieTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Plug.Session.COOKIE, as: CookieStore

  @default_opts [
    store: :cookie,
    key: "foobar",
    encryption_salt: "encrypted cookie salt",
    signing_salt: "signing salt",
    log: false
  ]

  @secret String.duplicate("abcdef0123456789", 8)
  @signing_opts Plug.Session.init(Keyword.put(@default_opts, :encrypt, false))
  @encrypted_opts Plug.Session.init(@default_opts)
  @prederived_opts Plug.Session.init([secret_key_base: @secret] ++ @default_opts)

  defmodule CustomSerializer do
    def encode(%{"foo" => "bar"}), do: {:ok, "encoded session"}
    def encode(%{"foo" => "baz"}), do: {:ok, "another encoded session"}
    def encode(%{}), do: {:ok, ""}
    def encode(_), do: :error

    def decode("encoded session"), do: {:ok, %{"foo" => "bar"}}
    def decode("another encoded session"), do: {:ok, %{"foo" => "baz"}}
    def decode(nil), do: {:ok, nil}
    def decode(_), do: :error
  end

  opts = Keyword.put(@default_opts, :serializer, CustomSerializer)
  @custom_serializer_opts Plug.Session.init(opts)

  defp sign_conn(conn, secret \\ @secret) do
    put_in(conn.secret_key_base, secret)
    |> Plug.Session.call(@signing_opts)
    |> fetch_session
  end

  defp encrypt_conn(conn) do
    put_in(conn.secret_key_base, @secret)
    |> Plug.Session.call(@encrypted_opts)
    |> fetch_session
  end

  defp prederived_conn(conn) do
    put_in(conn.secret_key_base, @secret)
    |> Plug.Session.call(@prederived_opts)
    |> fetch_session
  end

  defp custom_serialize_conn(conn) do
    put_in(conn.secret_key_base, @secret)
    |> Plug.Session.call(@custom_serializer_opts)
    |> fetch_session
  end

  def returns_arg(arg), do: arg

  defp apply_mfa({module, function, args}), do: apply(module, function, args)

  test "requires signing_salt option to be defined" do
    assert_raise ArgumentError, ~r/expects :signing_salt as option/, fn ->
      Plug.Session.init(Keyword.delete(@default_opts, :signing_salt))
    end
  end

  test "requires the secret to be at least 64 bytes" do
    assert_raise ArgumentError, ~r/to be at least 64 bytes/, fn ->
      conn(:get, "/")
      |> sign_conn("abcdef")
      |> put_session("foo", "bar")
      |> send_resp(200, "OK")
    end
  end

  test "defaults key generator opts" do
    key_generator_opts = CookieStore.init(@default_opts).key_opts
    assert key_generator_opts[:iterations] == 1000
    assert key_generator_opts[:length] == 32
    assert key_generator_opts[:digest] == :sha256
  end

  test "prederives keys is secret_key_base is available" do
    assert %{encryption_salt: {:prederived, _}, signing_salt: {:prederived, _}} =
             CookieStore.init([secret_key_base: @secret] ++ @default_opts)
  end

  test "uses specified key generator opts" do
    opts =
      @default_opts
      |> Keyword.put(:key_iterations, 2000)
      |> Keyword.put(:key_length, 64)
      |> Keyword.put(:key_digest, :sha)

    key_generator_opts = CookieStore.init(opts).key_opts
    assert key_generator_opts[:iterations] == 2000
    assert key_generator_opts[:length] == 64
    assert key_generator_opts[:digest] == :sha
  end

  test "requires serializer option to be an atom" do
    assert_raise ArgumentError, ~r/expects :serializer option to be a module/, fn ->
      Plug.Session.init(Keyword.put(@default_opts, :serializer, "CustomSerializer"))
    end
  end

  test "uses :external_term_format cookie serializer by default" do
    assert Plug.Session.init(@default_opts).store_config.serializer == :external_term_format
  end

  test "uses custom cookie serializer" do
    assert @custom_serializer_opts.store_config.serializer == CustomSerializer
  end

  test "uses MFAs for salts" do
    opts = [
      store: :cookie,
      key: "foobar",
      encryption_salt: {__MODULE__, :returns_arg, ["encrypted cookie salt"]},
      signing_salt: {__MODULE__, :returns_arg, ["signing salt"]}
    ]

    plug = Plug.Session.init(opts)
    assert apply_mfa(plug.store_config.encryption_salt) == "encrypted cookie salt"
    assert apply_mfa(plug.store_config.signing_salt) == "signing salt"
  end

  ## Signed

  test "session cookies are signed" do
    conn = %{secret_key_base: @secret}
    cookie = CookieStore.put(conn, nil, %{"foo" => "baz"}, @signing_opts.store_config)
    assert is_binary(cookie)
    assert CookieStore.get(conn, cookie, @signing_opts.store_config) == {:term, %{"foo" => "baz"}}
    assert CookieStore.get(conn, "bad", @signing_opts.store_config) == {nil, %{}}
  end

  test "gets and sets signed session cookie" do
    conn =
      conn(:get, "/")
      |> sign_conn()
      |> put_session("foo", "bar")
      |> send_resp(200, "")

    assert conn(:get, "/")
           |> recycle_cookies(conn)
           |> sign_conn()
           |> get_session("foo") == "bar"
  end

  test "deletes signed session cookie" do
    conn =
      conn(:get, "/")
      |> sign_conn()
      |> put_session("foo", "bar")
      |> configure_session(drop: true)
      |> send_resp(200, "")

    assert conn(:get, "/")
           |> recycle_cookies(conn)
           |> sign_conn()
           |> get_session("foo") == nil
  end

  ## Encrypted

  test "session cookies are encrypted" do
    conn = %{secret_key_base: @secret}
    cookie = CookieStore.put(conn, nil, %{"foo" => "baz"}, @encrypted_opts.store_config)
    assert is_binary(cookie)

    assert CookieStore.get(conn, cookie, @encrypted_opts.store_config) ==
             {:term, %{"foo" => "baz"}}

    assert CookieStore.get(conn, "bad", @encrypted_opts.store_config) == {nil, %{}}
  end

  test "gets and sets encrypted session cookie" do
    conn =
      conn(:get, "/")
      |> encrypt_conn()
      |> put_session("foo", "bar")
      |> send_resp(200, "")

    assert conn(:get, "/")
           |> recycle_cookies(conn)
           |> encrypt_conn()
           |> get_session("foo") == "bar"
  end

  test "deletes encrypted session cookie" do
    conn =
      conn(:get, "/")
      |> encrypt_conn()
      |> put_session("foo", "bar")
      |> configure_session(drop: true)
      |> send_resp(200, "")

    assert conn(:get, "/")
           |> recycle_cookies(conn)
           |> encrypt_conn()
           |> get_session("foo") == nil
  end

  ## Custom Serializer

  test "session cookies are serialized by the custom serializer" do
    conn = %{secret_key_base: @secret}
    cookie = CookieStore.put(conn, nil, %{"foo" => "baz"}, @custom_serializer_opts.store_config)
    assert is_binary(cookie)

    assert CookieStore.get(conn, cookie, @custom_serializer_opts.store_config) ==
             {:custom, %{"foo" => "baz"}}
  end

  test "gets and sets custom serialized session cookie" do
    conn =
      conn(:get, "/")
      |> custom_serialize_conn()
      |> put_session("foo", "bar")
      |> send_resp(200, "")

    assert conn(:get, "/")
           |> recycle_cookies(conn)
           |> custom_serialize_conn()
           |> get_session("foo") == "bar"
  end

  test "deletes custom serialized session cookie" do
    conn =
      conn(:get, "/")
      |> custom_serialize_conn()
      |> put_session("foo", "bar")
      |> configure_session(drop: true)
      |> send_resp(200, "")

    assert conn(:get, "/")
           |> recycle_cookies(conn)
           |> custom_serialize_conn()
           |> get_session("foo") == nil
  end

  # Prederivation

  test "gets and sets prederived session cookie" do
    conn =
      conn(:get, "/")
      |> prederived_conn()
      |> put_session("foo", "bar")
      |> send_resp(200, "")

    assert conn(:get, "/")
           |> recycle_cookies(conn)
           |> prederived_conn()
           |> get_session("foo") == "bar"
  end

  # Rotating options

  test "gets session cookie using rotating options" do
    v1_opts =
      Keyword.merge(@default_opts,
        encryption_salt: "encrypted cookie salt v1",
        signing_salt: "signing salt v1",
        secret_key_base: @secret
      )

    v1_conn =
      conn(:get, "/")
      |> Plug.Session.call(Plug.Session.init(v1_opts))
      |> fetch_session()
      |> put_session("foo", "bar")
      |> send_resp(200, "")

    # With different opts should not be able to read the cookie
    v2_opts =
      Keyword.merge(v1_opts,
        encryption_salt: nil,
        signing_salt: "signing salt v2",
        secret_key_base: @secret
      )

    v2_conn =
      conn(:get, "/")
      |> recycle_cookies(v1_conn)
      |> Plug.Session.call(Plug.Session.init(v2_opts))
      |> fetch_session()

    assert v2_conn
           |> get_session("foo") == nil

    # With rotating opts should be able to read the cookie
    v3_opts =
      Keyword.merge(v2_opts,
        rotating_options: [v1_opts]
      )

    v3_conn =
      conn(:get, "/")
      |> recycle_cookies(v1_conn)
      |> Plug.Session.call(Plug.Session.init(v3_opts))
      |> fetch_session()

    assert v3_conn
           |> get_session("foo") == "bar"

    # With rotating opts should set the cookie using main opts
    # v2_opts is the main opts
    # v1_opts is in rotating opts
    v4_conn =
      conn(:get, "/")
      |> recycle_cookies(v1_conn)
      |> Plug.Session.call(Plug.Session.init(v3_opts))
      |> fetch_session()
      |> put_session("foo", "bar")
      |> send_resp(200, "")

    assert conn(:get, "/")
           |> recycle_cookies(v4_conn)
           |> Plug.Session.call(Plug.Session.init(v1_opts))
           |> fetch_session()
           |> get_session("foo") == nil

    assert conn(:get, "/")
           |> recycle_cookies(v4_conn)
           |> Plug.Session.call(Plug.Session.init(v2_opts))
           |> fetch_session()
           |> get_session("foo") == "bar"
  end
end
