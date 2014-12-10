defmodule Plug.CSRFProtection do
  @moduledoc """
  Plug to protect from cross-site request forgery.

  For this plug to work, it expects a session to have been previously fetched.
  If a CSRF token in the session does not previously exist, a CSRF token will
  be generated and put into the session.

  When a token is invalid, an `InvalidCSRFTokenError` error is raised.

  The session's CSRF token will be compared with a token in the params with key
  "csrf_token" or a token in the request headers with key "x-csrf-token".

  Only GET and HEAD requests are unprotected.

  Javascript GET requests are only allowed if they are XHR requests. Otherwise,
  an `InvalidCrossOriginRequestError` error will be raised.

  You may disable this plug by doing `Plug.Conn.put_private(:plug_skip_csrf_protection, true)`.

  ## Examples

      plug Plug.CSRFProtection

  """

  import Plug.Conn
  @unprotected_methods ~w(HEAD GET)

  defmodule InvalidCSRFTokenError do
    @moduledoc "Error raised when CSRF token is invalid."
    message = "Invalid CSRF (Cross Site Forgery Protection) token. Make sure that all " <>
              "your non-HEAD and non-GET requests include the csrf_token as part of form " <>
              "params or as a value in your request's headers with the key 'x-csrf-token'"

    defexception message: message, plug_status: 403
  end

  defmodule InvalidCrossOriginRequestError do
    @moduledoc "Error raised when non-XHR requests are used for Javascript responses."
    message = "Security warning: an embedded <script> tag on another site requested " <>
              "protected JavaScript. If you know what you're doing, you may disable " <>
              "forgery protection for this route"

    defexception message: message, plug_status: 403
  end

  def init(opts), do: opts

  def call(conn, _opts) do
    csrf_token = get_session(conn, :csrf_token)

    if not verified_request?(conn, csrf_token) do
      raise InvalidCSRFTokenError
    end

    conn
    |> mark_for_cross_origin_check
    |> ensure_csrf_token(csrf_token)
  end

  defp verified_request?(conn, csrf_token) do
    conn.method in @unprotected_methods
      || valid_csrf_token?(csrf_token, conn.params["csrf_token"])
      || valid_csrf_token?(csrf_token, get_req_header(conn, "x-csrf-token") |> Enum.at(0))
      || plug_skip_csrf_protection?(conn)
  end

  defp plug_skip_csrf_protection?(%{private: %{plug_skip_csrf_protection: true}}), do: true
  defp plug_skip_csrf_protection?(_), do: false

  defp valid_csrf_token?(csrf_token, user_token) do
    csrf_token && user_token &&
      Plug.Crypto.secure_compare(csrf_token, user_token)
  end

  # Cross origin

  def mark_for_cross_origin_check(conn) do
    if conn.method == "GET" and not xhr?(conn) and not plug_skip_csrf_protection?(conn) do
      register_before_send conn, &check_for_cross_origin/1
    else
      conn
    end
  end

  defp xhr?(conn) do
    "XMLHttpRequest" in get_req_header(conn, "x-requested-with")
  end

  defp check_for_cross_origin(conn) do
    js? = Enum.any? get_resp_header(conn, "content-type"),
                    &String.starts_with?(&1, ["text/javascript", "application/javascript"])

    if js? do
      raise InvalidCrossOriginRequestError
    else
      conn
    end
  end

  # Token generation

  defp ensure_csrf_token(conn, csrf_token) do
    if csrf_token do
      conn
    else
      put_session(conn, :csrf_token, generate_token())
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.encode64
  end
end
