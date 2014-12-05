defmodule Plug.CsrfProtection do
  alias Plug.Conn

  @moduledoc """
  Plug to protect from cross-site request forgery.

  For this plug to work, it expects a session to have been previously fetched.
  If a CSRF token in the session does not previously exist, a CSRF token will
  be generated and put into the session.

  When a token is invalid, an InvalidAuthenticityToken error is raised.

  The session's CSRF token will be compared with a token in the params with key
  "csrf-token" or a token in the request headers with key 'X-CSRF-Token'.

  Only POST, PUT, PATCH and DELETE are protected methods. DELETE methods need
  a token in the request header to be validated since it doesn't accept params.

  ## Examples

      plug Plug.CsrfProtection

  """
  @unprotected_methods ~w(HEAD GET)

  defmodule InvalidAuthenticityToken do
    @moduledoc """
    Error raised when CSRF token is invalid.
    """
    @invalid_token_error_message
      "Invalid authenticity token. Make sure that all your non-HEAD and non-GET" <>
      "requests include the authenticity token as part of form params or as a" <>
      "value in your request's headers with the key 'X-CSRF-Token'."

    defexception message: @invalid_token_error_message, plug_status: 403
  end

  def init(opts), do: opts

  def call(%Conn{method: method} = conn, _opts) when not method in @unprotected_methods do
    if verified_request?(conn) do
      conn
    else
      raise InvalidAuthenticityToken
    end
  end

  def call(conn, _opts), do: ensure_csrf_token(conn)

  defp verified_request?(conn) do
    valid_authenticity_token?(conn, conn.params["csrf_token"]) ||
      valid_token_in_header?(conn)
  end

  defp valid_token_in_header?(conn) do
    header_token = Conn.get_req_header(conn, "X-CSRF-Token") |> Enum.at(0)
    valid_authenticity_token?(conn, header_token)
  end
  defp valid_authenticity_token?(_conn, nil), do: false
  defp valid_authenticity_token?(conn, token), do: get_csrf_token(conn) == token

  def get_csrf_token(conn), do: Conn.get_session(conn, :csrf_token)

  # TOKEN GENERATION

  defp ensure_csrf_token(conn) do
    if get_csrf_token(conn) do
      conn
    else
      Conn.put_session(conn, :csrf_token, generate_token(token_length))
    end
  end

  defp generate_token(n) when is_integer(n) do
    :crypto.strong_rand_bytes(n) |> Base.encode64
  end

  defp token_length, do: 32
end
