defmodule Plug.CSRFProtection do
  @moduledoc """
  Plug to protect from cross-site request forgery.

  This plug stores the CSRF token in a cookie during HEAD and GET requests
  and compare the value of the cookie with the token given as parameter or
  as part the request header as "x-csrf-token" during POST/PUT/etc requests.
  If the token is invalid, InvalidCSRFTokenError` is raised.

  Javascript GET requests are only allowed if they are XHR requests.
  Otherwise, an `InvalidCrossOriginRequestError` error will be raised.

  You may disable this plug in certain occasions, usually during tests,
  by doing:

      Plug.Conn.put_private(:plug_skip_csrf_protection, true)

  ## Options

    * `:name` - the name of the cookie, defaults to "_csrf_token"
    * `:domain` - the domain of the csrf cookie
    * `:path` - the path the cookie applies to
    * `:http_only` - if the cookie should be http only (by default is false)

  ## Examples

      plug :fetch_cookies
      plug :fetch_params
      plug Plug.CSRFProtection

  """

  import Plug.Conn
  @unprotected_methods ~w(HEAD GET)

  defmodule InvalidCSRFTokenError do
    @moduledoc "Error raised when CSRF token is invalid."
    message = "Invalid CSRF (Cross Site Forgery Protection) token. Make sure that all " <>
              "your non-HEAD and non-GET requests include the '_csrf_token' as part of form " <>
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

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, opts) do
    name = Keyword.get(opts, :name, "_csrf_token")
    csrf_token = Map.get(conn.req_cookies, name)

    if not verified_request?(conn, csrf_token) do
      raise InvalidCSRFTokenError
    end

    conn
    |> mark_for_cross_origin_check
    |> ensure_csrf_token(name, csrf_token, opts)
  end

  defp verified_request?(conn, csrf_token) do
    conn.method in @unprotected_methods
      || valid_csrf_token?(csrf_token, conn.params["_csrf_token"])
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

  defp mark_for_cross_origin_check(conn) do
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

  defp ensure_csrf_token(conn, name, csrf_token, opts) do
    if csrf_token do
      conn
    else
      opts = Keyword.put_new(opts, :http_only, false)
      put_resp_cookie(conn, name, generate_token(), opts)
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.encode64
  end
end
