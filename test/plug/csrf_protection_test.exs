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
  @csrf_token "hello123"

  def call(conn) do
    put_in(conn.secret_key_base, @secret)
    |> fetch_params
    |> Plug.Session.call(@default_opts)
    |> fetch_session
    |> CSRFProtection.call([])
    |> maybe_get_token
    |> put_resp_content_type(conn.assigns[:content_type] || "text/html")
    |> send_resp(200, "ok")
  end

  def call(conn, old_conn) do
    conn
    |> recycle_cookies(old_conn)
    |> call()
  end

  defp maybe_get_token(conn) do
    case conn.params["token"] do
      "get"    -> CSRFProtection.get_csrf_token()
      "delete" -> CSRFProtection.delete_csrf_token()
      _        -> :ok
    end

    conn
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
      |> call(old_conn)
    end

    assert_raise InvalidCSRFTokenError, fn ->
      conn(:post, "/", %{})
      |> call(old_conn)
    end
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

    conn = conn(:get, "/?token=delete") |> call(conn)
    refute conn.halted
    refute get_session(conn, "_csrf_token")
  end

  test "protected requests with valid token in params are allowed" do
    old_conn = conn(:get, "/?token=get") |> call
    params = %{_csrf_token: get_session(old_conn, "_csrf_token")}

    conn = conn(:post, "/", params) |> call(old_conn)
    refute conn.halted

    conn = conn(:put, "/", params) |> call(old_conn)
    refute conn.halted

    conn = conn(:patch, "/", params) |> call(old_conn)
    refute conn.halted
  end

  test "protected requests with valid token in header are allowed" do
    old_conn = conn(:get, "/?token=get") |> call
    csrf_token = get_session(old_conn, "_csrf_token")

    conn =
      conn(:post, "/")
      |> put_req_header("x-csrf-token", csrf_token)
      |> call(old_conn)
    refute conn.halted

    conn =
      conn(:put, "/")
      |> put_req_header("x-csrf-token", csrf_token)
      |> call(old_conn)
    refute conn.halted

    conn =
      conn(:patch, "/")
      |> put_req_header("x-csrf-token", csrf_token)
      |> call(old_conn)
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
