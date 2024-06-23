defmodule Plug.CSRFProtectionTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Plug.CSRFProtection
  alias Plug.CSRFProtection.InvalidCSRFTokenError
  alias Plug.CSRFProtection.InvalidCrossOriginRequestError

  @default_opts Plug.Session.init(
                  store: :cookie,
                  key: "foobar",
                  encryption_salt: "cookie store encryption salt",
                  signing_salt: "cookie store signing salt",
                  encrypt: true
                )

  @secret String.duplicate("abcdef0123456789", 8)

  def call(conn, csrf_plug_opts \\ []) do
    conn
    |> call_csrf_with_session(csrf_plug_opts)
    |> handle_token
  end

  def call_with_invalid_token(conn) do
    conn
    |> call_csrf_with_session([])
    |> put_session("_csrf_token", "invalid")
    |> handle_token
  end

  def call_with_old_conn(conn, old_conn, csrf_plug_opts \\ []) do
    conn
    |> recycle_cookies(old_conn)
    |> call(csrf_plug_opts)
  end

  defp call_csrf_with_session(conn, csrf_plug_opts) do
    conn.secret_key_base
    |> put_in(@secret)
    |> fetch_query_params
    |> Plug.Session.call(@default_opts)
    |> fetch_session
    |> put_session("key", "val")
    |> CSRFProtection.call(CSRFProtection.init(csrf_plug_opts))
    |> put_resp_content_type(conn.assigns[:content_type] || "text/html")
  end

  defp handle_token(conn) do
    case conn.params["token"] do
      "get" ->
        send_resp(conn, 200, CSRFProtection.get_csrf_token())

      "process_get" ->
        dumped = Plug.CSRFProtection.dump_state()
        secret_key_base = conn.secret_key_base

        token =
          fn ->
            Plug.CSRFProtection.load_state(secret_key_base, dumped)
            Plug.CSRFProtection.get_csrf_token()
          end
          |> Task.async()
          |> Task.await()

        send_resp(conn, 200, token)

      "get_for" ->
        send_resp(conn, 200, CSRFProtection.get_csrf_token_for("//www.example.com"))

      "get_for_invalid" ->
        send_resp(conn, 200, CSRFProtection.get_csrf_token_for("//www.evil.com"))

      "delete" ->
        CSRFProtection.delete_csrf_token()
        send_resp(conn, 200, "")

      _ ->
        send_resp(conn, 200, "")
    end
  end

  test "token has no padding" do
    refute CSRFProtection.get_csrf_token() =~ "="
  end

  test "token is stored in process dictionary" do
    assert CSRFProtection.get_csrf_token() == CSRFProtection.get_csrf_token()

    token = CSRFProtection.get_csrf_token()
    CSRFProtection.delete_csrf_token()
    assert token != CSRFProtection.get_csrf_token()
  end

  test "token is stored in process dictionary per host" do
    Process.put(:plug_csrf_token_per_host, %{secret_key_base: @secret})
    token = CSRFProtection.get_csrf_token()

    assert CSRFProtection.get_csrf_token() == token
    assert CSRFProtection.get_csrf_token_for("/") == token
    assert CSRFProtection.get_csrf_token_for("/foo") == token
    assert CSRFProtection.get_csrf_token_for(%URI{host: nil}) == token
    assert CSRFProtection.get_csrf_token_for("//www.example.com") != token
    assert CSRFProtection.get_csrf_token_for("http://www.example.com") != token
    assert CSRFProtection.get_csrf_token_for(%URI{host: "www.example.com"}) != token

    host_token = CSRFProtection.get_csrf_token_for("http://www.example.com")
    assert CSRFProtection.get_csrf_token_for(%URI{host: "www.example.com"}) == host_token
    CSRFProtection.delete_csrf_token()
    assert CSRFProtection.get_csrf_token_for("http://www.example.com") != host_token
  end

  test "cannot generate token from missing host in process" do
    msg = ~r|invoked in a separate process than the one that started the request|

    assert_raise RuntimeError, msg, fn ->
      assert CSRFProtection.get_csrf_token_for(%URI{host: "http://www.example.com"})
    end
  end

  test "raise error for missing authenticity token in session" do
    assert_raise InvalidCSRFTokenError, fn ->
      call(conn(:post, "/", %{}))
    end

    assert_raise InvalidCSRFTokenError, fn ->
      call(conn(:post, "/", %{_csrf_token: "foo"}))
    end
  end

  test "raise error for invalid authenticity token in params" do
    old_conn = call(conn(:get, "/"))

    assert_raise InvalidCSRFTokenError, fn ->
      call_with_old_conn(conn(:post, "/", ""), old_conn)
    end

    assert_raise InvalidCSRFTokenError, fn ->
      call_with_old_conn(conn(:post, "/", %{_csrf_token: "foo"}), old_conn)
    end

    assert_raise InvalidCSRFTokenError, fn ->
      call_with_old_conn(conn(:post, "/", %{}), old_conn)
    end
  end

  test "error is raised when CSRF token payload is not a Base64 encoded string" do
    old_conn = call(conn(:get, "/?token=get_for"))

    # Replace the token payload with a string that is not Base64 encoded.
    [protected, _payload, signature] = String.split(old_conn.resp_body, ".")
    csrf_token = Enum.join([protected, "a", signature], ".")

    assert_raise InvalidCSRFTokenError, fn ->
      call_with_old_conn(conn(:post, "/", %{_csrf_token: csrf_token}), old_conn)
    end
  end

  test "raise error when unrecognized option is sent" do
    token = CSRFProtection.get_csrf_token()

    assert_raise ArgumentError, ~r/option :with should be/, fn ->
      call(conn(:post, "/", %{_csrf_token: token}), with: :unknown_opt)
    end
  end

  test "clear session for missing authenticity token in session" do
    assert conn(:post, "/", %{})
           |> call(with: :clear_session)
           |> get_session("key") == nil

    assert conn(:post, "/", %{_csrf_token: "foo"})
           |> call(with: :clear_session)
           |> get_session("key") == nil
  end

  test "clear session for invalid authenticity token in params" do
    old_conn = call(conn(:get, "/"))

    assert conn(:post, "/", %{_csrf_token: "foo"})
           |> call_with_old_conn(old_conn, with: :clear_session)
           |> get_session("key") == nil

    assert conn(:post, "/", %{})
           |> call_with_old_conn(old_conn, with: :clear_session)
           |> get_session("key") == nil
  end

  test "clear session only for the current running connection" do
    conn = call(conn(:get, "/?token=get"))
    csrf_token = conn.resp_body

    conn = call_with_old_conn(conn(:post, "/", %{}), conn, with: :clear_session)
    assert get_session(conn, "key") == nil

    assert conn(:post, "/", %{})
           |> put_req_header("x-csrf-token", csrf_token)
           |> call_with_old_conn(conn, with: :clear_session)
           |> get_session("key") == "val"
  end

  test "unprotected requests are always valid" do
    conn = call(conn(:get, "/"))
    refute conn.halted
    refute get_session(conn, "_csrf_token")

    conn = call(conn(:head, "/"))
    refute conn.halted
    refute get_session(conn, "_csrf_token")

    conn = call(conn(:options, "/"))
    refute conn.halted
    refute get_session(conn, "_csrf_token")
  end

  test "tokens are generated and deleted on demand" do
    conn = call(conn(:get, "/?token=get"))
    refute conn.halted
    assert get_session(conn, "_csrf_token")

    conn = call_with_old_conn(conn(:get, "/?token=delete"), conn)
    refute conn.halted
    refute get_session(conn, "_csrf_token")
  end

  test "tokens are generated and deleted with custom key" do
    conn = call(conn(:get, "/?token=get"), session_key: "my_csrf_token")
    refute conn.halted
    token = conn.resp_body
    assert byte_size(token) == 56
    refute get_session(conn, "_csrf_token")
    assert get_session(conn, "my_csrf_token")

    conn = call_with_old_conn(conn(:get, "/?token=delete"), conn, session_key: "my_csrf_token")
    refute conn.halted
    refute get_session(conn, "my_csrf_token")
  end

  test "tokens are ignored when invalid and deleted on demand" do
    conn = call_with_invalid_token(conn(:get, "/?token=get"))
    conn = call_with_old_conn(conn(:get, "/?token=get"), conn)
    assert get_session(conn, "_csrf_token")
  end

  test "generated tokens are always masked" do
    conn1 = call(conn(:get, "/?token=get"))
    assert byte_size(conn1.resp_body) == 56
    state = CSRFProtection.dump_state_from_session(get_session(conn1, "_csrf_token"))
    assert CSRFProtection.valid_state_and_csrf_token?(state, conn1.resp_body)

    conn2 = call(conn(:get, "/?token=get"))
    assert byte_size(conn2.resp_body) == 56
    state = CSRFProtection.dump_state_from_session(get_session(conn2, "_csrf_token"))
    assert CSRFProtection.valid_state_and_csrf_token?(state, conn2.resp_body)

    assert conn1.resp_body != conn2.resp_body
  end

  test "valid_state_and_csrf_token?/2 does not return truthy value when given CSRF token that is not Base64 encoded" do
    conn = call(conn(:get, "/?token=get"))
    assert byte_size(conn.resp_body) == 56
    state = CSRFProtection.dump_state_from_session(get_session(conn, "_csrf_token"))

    # Replace the first byte of the CSRF token with a character that is not in
    # the Base64 alphabet.
    <<_head, rest::binary>> = conn.resp_body
    refute CSRFProtection.valid_state_and_csrf_token?(state, <<"!", rest::binary>>)
  end

  test "protected requests with token from another process in params are allowed" do
    old_conn = call(conn(:get, "/?token=process_get"))
    params = %{_csrf_token: old_conn.resp_body}

    conn = call_with_old_conn(conn(:post, "/", params), old_conn)
    refute conn.halted

    conn = call_with_old_conn(conn(:put, "/", params), old_conn)
    refute conn.halted

    conn = call_with_old_conn(conn(:patch, "/", params), old_conn)
    refute conn.halted
  end

  test "protected requests with valid host token in params are allowed" do
    old_conn = call(conn(:get, "/?token=get_for"))
    params = %{_csrf_token: old_conn.resp_body}

    conn = call_with_old_conn(conn(:post, "/", params), old_conn)
    refute conn.halted

    conn = call_with_old_conn(conn(:put, "/", params), old_conn)
    refute conn.halted

    conn = call_with_old_conn(conn(:patch, "/", params), old_conn)
    refute conn.halted
  end

  @tag :capture_log
  test "protected requests with invalid host token in params are not allowed" do
    old_conn = call(conn(:get, "/?token=get_for_invalid"))
    params = %{_csrf_token: old_conn.resp_body}

    assert_raise InvalidCSRFTokenError, fn ->
      call_with_old_conn(conn(:post, "/", params), old_conn)
    end

    assert_raise InvalidCSRFTokenError, fn ->
      call_with_old_conn(conn(:put, "/", params), old_conn)
    end

    assert_raise InvalidCSRFTokenError, fn ->
      call_with_old_conn(conn(:patch, "/", params), old_conn)
    end

    assert_raise InvalidCSRFTokenError, fn ->
      call_with_old_conn(conn(:patch, "/", params), old_conn, allow_hosts: [".another.com"])
    end
  end

  test "protected requests with invalid host token when explicitly allowed" do
    old_conn = call(conn(:get, "/?token=get_for_invalid"))
    params = %{_csrf_token: old_conn.resp_body}

    conn = call_with_old_conn(conn(:post, "/", params), old_conn, allow_hosts: [".evil.com"])
    refute conn.halted

    conn = call_with_old_conn(conn(:post, "/", params), old_conn, allow_hosts: ["www.evil.com"])
    refute conn.halted
  end

  test "protected requests with valid token in params are allowed" do
    old_conn = call(conn(:get, "/?token=get"))
    params = %{_csrf_token: old_conn.resp_body}

    conn = call_with_old_conn(conn(:post, "/", params), old_conn)
    refute conn.halted

    conn = call_with_old_conn(conn(:put, "/", params), old_conn)
    refute conn.halted

    conn = call_with_old_conn(conn(:patch, "/", params), old_conn)
    refute conn.halted
  end

  test "protected requests with valid token in header are allowed" do
    old_conn = call(conn(:get, "/?token=get"))
    csrf_token = old_conn.resp_body

    conn =
      conn(:post, "/", %{})
      |> put_req_header("x-csrf-token", csrf_token)
      |> call_with_old_conn(old_conn)

    refute conn.halted

    conn =
      conn(:put, "/", %{})
      |> put_req_header("x-csrf-token", csrf_token)
      |> call_with_old_conn(old_conn)

    refute conn.halted

    conn =
      conn(:patch, "/", %{})
      |> put_req_header("x-csrf-token", csrf_token)
      |> call_with_old_conn(old_conn)

    refute conn.halted
  end

  test "non-XHR Javascript GET requests are forbidden" do
    assert_raise InvalidCrossOriginRequestError, fn ->
      conn(:get, "/") |> assign(:content_type, "application/javascript") |> call()
    end

    assert_raise InvalidCrossOriginRequestError, fn ->
      conn(:get, "/") |> assign(:content_type, "text/javascript") |> call()
    end
  end

  test "only XHR Javascript GET requests are allowed" do
    conn =
      conn(:get, "/")
      |> assign(:content_type, "text/javascript")
      |> put_req_header("x-requested-with", "XMLHttpRequest")
      |> call()

    refute conn.halted
  end

  test "is skipped when plug_skip_csrf_protection is true" do
    conn =
      conn(:get, "/?token=get")
      |> put_private(:plug_skip_csrf_protection, true)
      |> call()

    assert get_session(conn, "_csrf_token")

    conn =
      conn(:post, "/?token=get", %{})
      |> put_private(:plug_skip_csrf_protection, true)
      |> call()

    assert get_session(conn, "_csrf_token")

    conn =
      conn(:get, "/?token=get")
      |> put_private(:plug_skip_csrf_protection, true)
      |> assign(:content_type, "text/javascript")
      |> call()

    assert get_session(conn, "_csrf_token")
  end

  test "does not delete token if the plug is invoked twice" do
    conn =
      conn(:get, "/?token=get")
      |> recycle_cookies(call(conn(:get, "/?token=get")))
      |> call_csrf_with_session([])
      |> CSRFProtection.call(CSRFProtection.init([]))
      |> handle_token

    assert get_session(conn, "_csrf_token")
  end
end
