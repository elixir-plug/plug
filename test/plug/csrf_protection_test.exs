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
    do_call(conn, csrf_plug_opts)
    |> handle_token
  end

  def call_with_invalid_token(conn) do
    do_call(conn, [])
    |> put_session("_csrf_token", "invalid")
    |> handle_token
  end

  defp do_call(conn, csrf_plug_opts) do
    put_in(conn.secret_key_base, @secret)
    |> fetch_query_params
    |> Plug.Session.call(@default_opts)
    |> fetch_session
    |> put_session("key", "val")
    |> CSRFProtection.call(csrf_plug_opts)
    |> put_resp_content_type(conn.assigns[:content_type] || "text/html")
  end

  def call_with_old_conn(conn, old_conn, csrf_plug_opts \\ []) do
    conn
    |> recycle_cookies(old_conn)
    |> call(csrf_plug_opts)
  end

  defp handle_token(conn) do
    case conn.params["token"] do
      "get" ->
        send_resp(conn, 200, CSRFProtection.get_csrf_token())
      "delete" ->
        CSRFProtection.delete_csrf_token()
        send_resp(conn, 200, "")
      _ ->
        send_resp(conn, 200, "")
    end
  end

  test "token is stored in process dictionary" do
    assert CSRFProtection.get_csrf_token() ==
           CSRFProtection.get_csrf_token()

    t1 = CSRFProtection.get_csrf_token
    CSRFProtection.delete_csrf_token
    assert t1 != CSRFProtection.get_csrf_token
  end

  test "raise error for missing authenticity token in session" do
    assert_raise InvalidCSRFTokenError, fn ->
      conn(:post, "/") |> call()
    end

    assert_raise InvalidCSRFTokenError, fn ->
      conn(:post, "/", %{_csrf_token: "foo"}) |> call()
    end
  end

  test "raise error for invalid authenticity token in params" do
    old_conn = call(conn(:get, "/"))

    assert_raise InvalidCSRFTokenError, fn ->
      conn(:post, "/", %{_csrf_token: "foo"})
      |> call_with_old_conn(old_conn)
    end

    assert_raise InvalidCSRFTokenError, fn ->
      conn(:post, "/", %{})
      |> call_with_old_conn(old_conn)
    end
  end

  test "raise error when unrecognized option is sent" do
    assert_raise ArgumentError, fn ->
      conn(:post, "/") |> call(with: :unknown_opt)
    end
  end

  test "clear session for missing authenticity token in session" do
    assert conn(:post, "/")
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
    conn = conn(:get, "/?token=get") |> call
    csrf_token = conn.resp_body

    conn = conn(:post, "/") |> call_with_old_conn(conn, with: :clear_session)
    assert conn |> get_session("key") == nil

    assert conn(:post, "/")
           |> put_req_header("x-csrf-token", csrf_token)
           |> call_with_old_conn(conn, with: :clear_session)
           |> get_session("key") == "val"
  end

  test "unprotected requests are always valid" do
    conn = conn(:get, "/") |> call()
    refute conn.halted
    refute get_session(conn, "_csrf_token")

    conn = conn(:head, "/") |> call()
    refute conn.halted
    refute get_session(conn, "_csrf_token")

    conn = conn(:options, "/") |> call()
    refute conn.halted
    refute get_session(conn, "_csrf_token")
  end

  test "tokens are generated and deleted on demand" do
    conn = conn(:get, "/?token=get") |> call()
    refute conn.halted
    assert get_session(conn, "_csrf_token")

    conn = conn(:get, "/?token=delete") |> call_with_old_conn(conn)
    refute conn.halted
    refute get_session(conn, "_csrf_token")
  end

  test "tokens are ignored when invalid and deleted on demand" do
    conn = conn(:get, "/?token=get") |> call_with_invalid_token()
    conn = conn(:get, "/?token=get") |> call_with_old_conn(conn)
    assert get_session(conn, "_csrf_token")
  end

  test "generated tokens are always masked" do
    conn1 = conn(:get, "/?token=get") |> call()
    assert byte_size(conn1.resp_body) == 56

    conn2 = conn(:get, "/?token=get") |> call()
    assert byte_size(conn2.resp_body) == 56

    assert conn1.resp_body != conn2.resp_body
  end

  test "protected requests with valid token in params are allowed" do
    old_conn = conn(:get, "/?token=get") |> call
    params = %{_csrf_token: old_conn.resp_body}

    conn = conn(:post, "/", params) |> call_with_old_conn(old_conn)
    refute conn.halted

    conn = conn(:put, "/", params) |> call_with_old_conn(old_conn)
    refute conn.halted

    conn = conn(:patch, "/", params) |> call_with_old_conn(old_conn)
    refute conn.halted
  end

  test "protected requests with valid token in header are allowed" do
    old_conn = conn(:get, "/?token=get") |> call
    csrf_token = old_conn.resp_body

    conn =
      conn(:post, "/")
      |> put_req_header("x-csrf-token", csrf_token)
      |> call_with_old_conn(old_conn)
    refute conn.halted

    conn =
      conn(:put, "/")
      |> put_req_header("x-csrf-token", csrf_token)
      |> call_with_old_conn(old_conn)
    refute conn.halted

    conn =
      conn(:patch, "/")
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

  test "csrf plug is skipped when plug_skip_csrf_protection is true" do
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
end
