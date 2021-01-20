defmodule Plug.CSRFProtection do
  @moduledoc """
  Plug to protect from cross-site request forgery.

  For this plug to work, it expects a session to have been
  previously fetched. It will then compare the token stored
  in the session with the one sent by the request to determine
  the validity of the request. For an invalid request the action
  taken is based on the `:with` option.

  The token may be sent by the request either via the params
  with key "_csrf_token" or a header with name "x-csrf-token".

  GET requests are not protected, as they should not have any
  side-effect or change your application state. JavaScript
  requests are an exception: by using a script tag, external
  websites can embed server-side generated JavaScript, which
  can leak information. For this reason, this plug also forbids
  any GET JavaScript request that is not XHR (or AJAX).

  Note that it is recommended to enable CSRFProtection whenever
  a session is used, even for JSON requests. For example, Chrome
  had a bug that allowed POST requests to be triggered with
  arbitrary content-type, making JSON exploitable. More info:
  https://bugs.chromium.org/p/chromium/issues/detail?id=490015

  Finally, we recommend developers to invoke `delete_csrf_token/0`
  every time after they log a user in, to avoid CSRF fixation
  attacks.

  ## Token generation

  This plug won't generate tokens automatically. Instead, tokens
  will be generated only when required by calling `get_csrf_token/0`.
  In case you are generating the token for certain specific URL,
  you should use `get_csrf_token_for/1` as that will avoid tokens
  from being leaked to other applications.

  Once a token is generated, it is cached in the process dictionary.
  The CSRF token is usually generated inside forms which may be
  isolated from `Plug.Conn`. Storing them in the process dictionary
  allows them to be generated as a side-effect only when necessary,
  becoming one of those rare situations where using the process
  dictionary is useful.

  ## Cross-host protection

  If you are sending data to a full URI, such as `//subdomain.host.com/path`
  or `//external.com/path`, instead of a simple path such as `/path`, you may
  want to consider using `get_csrf_token_for/1`, as that will encode the host
  in the CSRF token. Once received, Plug will only consider the CSRF token to
  be valid if the `host` encoded in the token is the same as the one in
  `conn.host`.

  Therefore, if you get a warning that the host does not match, it is either
  because someone is attempting to steal CSRF tokens or because you have a
  misconfigured host configuration.

  For example, if you are running your application behind a proxy, the browser
  will send a request to the proxy with `www.example.com` but the proxy will
  request you using an internal IP. In such cases, it is common for proxies
  to attach information such as `"x-forwarded-host"` that contains the original
  host.

  This may also happen on redirects. If you have a POST request to `foo.example.com`
  that redirects to `bar.example.com` with status 307, the token will contain a
  different host than the one in the request.

  You can pass the `:allow_hosts` option to control any host that you may want
  to allow. The values in `:allow_hosts` may either be a full host name or a
  host suffix. For example: `["www.example.com", ".subdomain.example.com"]`
  will allow the exact host of `"www.example.com"` and any host that ends with
  `".subdomain.example.com"`.

  ## Options

    * `:session_key` - the name of the key in session to store the token under
    * `:allow_hosts` - a list with hosts to allow on cross-host tokens
    * `:with` - should be one of `:exception` or `:clear_session`. Defaults to
    `:exception`.
      * `:exception` -  for invalid requests, this plug will raise
      `Plug.CSRFProtection.InvalidCSRFTokenError`.
      * `:clear_session` -  for invalid requests, this plug will set an empty
      session for only this request. Also any changes to the session during this
      request will be ignored.

  ## Disabling

  You may disable this plug by doing
  `Plug.Conn.put_private(conn, :plug_skip_csrf_protection, true)`. This was made
  available for disabling `Plug.CSRFProtection` in tests and not for dynamically
  skipping `Plug.CSRFProtection` in production code. If you want specific routes to
  skip `Plug.CSRFProtection`, then use a different stack of plugs for that route that
  does not include `Plug.CSRFProtection`.

  ## Examples

      plug Plug.Session, ...
      plug :fetch_session
      plug Plug.CSRFProtection

  """

  import Plug.Conn
  require Bitwise
  require Logger

  alias Plug.Crypto.KeyGenerator
  alias Plug.Crypto.MessageVerifier

  @behaviour Plug
  @unprotected_methods ~w(HEAD GET OPTIONS)
  @digest Base.url_encode64("HS256", padding: false) <> "."

  # The token size value should not generate padding
  @token_size 18
  @encoded_token_size 24
  @double_encoded_token_size 32

  defmodule InvalidCSRFTokenError do
    @moduledoc "Error raised when CSRF token is invalid."

    message =
      "invalid CSRF (Cross Site Request Forgery) token, please make sure that:\n\n" <>
        "  * The session cookie is being sent and session is loaded\n" <>
        "  * The request include a valid '_csrf_token' param or 'x-csrf-token' header"

    defexception message: message, plug_status: 403
  end

  defmodule InvalidCrossOriginRequestError do
    @moduledoc "Error raised when non-XHR requests are used for Javascript responses."

    message =
      "security warning: an embedded <script> tag on another site requested " <>
        "protected JavaScript (if you know what you're doing, disable forgery " <>
        "protection for this route)"

    defexception message: message, plug_status: 403
  end

  ## API

  @doc """
  Load CSRF state into the process dictionary.

  This can be used to load CSRF state into another process.
  See `dump_state/0` and `dump_state_from_session/2` for dumping it.

  ## Examples

  To dump the state from the current process and load into another one:

      csrf_state = Plug.CSRFProtection.dump_state()
      secret_key_base = conn.secret_key_base

      Task.async(fn ->
        Plug.CSRFProtection.load_state(secret_key_base, csrf_state)
      end)

  If you have a session but the CSRF state was not loaded into the
  current process, you can dump the state from the session:

      csrf_state = Plug.CSRFProtection.dump_state_from_session(session["_csrf_token"])

      Task.async(fn ->
        Plug.CSRFProtection.load_state(secret_key_base, csrf_state)
      end)

  """
  def load_state(secret_key_base, csrf_state) when is_binary(csrf_state) or is_nil(csrf_state) do
    Process.put(:plug_unmasked_csrf_token, csrf_state)
    Process.put(:plug_csrf_token_per_host, %{secret_key_base: secret_key_base})
    :ok
  end

  @doc """
  Dump CSRF state so it can be loaded in another process.

  This function must be called after the `Plug.CSRFProtection`
  plug is invoked. If a token was not yet computed, it will be.

  See `load_state/2` for more information.
  """
  def dump_state() do
    unmasked_csrf_token()
  end

  @doc """
  Dumps the CSRF state from the connection.

  It expects the value of `get_session(conn, "_csrf_token")`.
  It returns `nil` if there is no state in the session.
  """
  def dump_state_from_session(session_token) do
    if is_binary(session_token) and byte_size(session_token) == @encoded_token_size do
      session_token
    end
  end

  @doc """
  Validates the `state` is valid against the given `csrf_token`.
  """
  def valid_state_and_csrf_token?(state, csrf_token) do
    with <<state_token::@encoded_token_size-binary>> <-
           state,
         <<user_token::@double_encoded_token_size-binary, mask::@encoded_token_size-binary>> <-
           csrf_token do
      valid_masked_token?(state_token, user_token, mask)
    else
      _ -> false
    end
  end

  @doc """
  Gets the CSRF token.

  Generates a token and stores it in the process
  dictionary if one does not exist.
  """
  def get_csrf_token do
    if token = Process.get(:plug_masked_csrf_token) do
      token
    else
      token = mask(unmasked_csrf_token())
      Process.put(:plug_masked_csrf_token, token)
      token
    end
  end

  @doc """
  Gets the CSRF token for the associated URL (as a string or a URI struct).

  If the URL has a host, a CSRF token that is tied to that
  host will be generated. If it is a relative path URL, a
  simple token emitted with `get_csrf_token/0` will be used.
  """
  def get_csrf_token_for(url) when is_binary(url) do
    case url do
      <<"/">> -> get_csrf_token()
      <<"/", not_slash, _::binary>> when not_slash != ?/ -> get_csrf_token()
      _ -> get_csrf_token_for(URI.parse(url))
    end
  end

  def get_csrf_token_for(%URI{host: nil}) do
    get_csrf_token()
  end

  def get_csrf_token_for(%URI{host: host}) do
    case Process.get(:plug_csrf_token_per_host) do
      %{^host => token} ->
        token

      %{secret_key_base: secret} = secrets ->
        unmasked = unmasked_csrf_token()
        message = generate_token() <> host
        key = KeyGenerator.generate(secret, unmasked)
        token = MessageVerifier.sign(message, key)
        Process.put(:plug_csrf_token_per_host, Map.put(secrets, host, token))
        token

      _ ->
        raise "cannot generate CSRF token for a host because get_csrf_token_for/1 is invoked " <>
                "in a separate process than the one that started the request"
    end
  end

  @doc """
  Deletes the CSRF token from the process dictionary.

  This will force the token to be deleted once the response is sent.
  """
  def delete_csrf_token do
    case Process.get(:plug_csrf_token_per_host) do
      %{secret_key_base: secret_key_base} ->
        Process.put(:plug_csrf_token_per_host, %{secret_key_base: secret_key_base})
        Process.put(:plug_unmasked_csrf_token, :delete)

      _ ->
        :ok
    end

    Process.delete(:plug_masked_csrf_token)
  end

  ## Plug

  @impl true
  def init(opts) do
    session_key = Keyword.get(opts, :session_key, "_csrf_token")
    mode = Keyword.get(opts, :with, :exception)
    allow_hosts = Keyword.get(opts, :allow_hosts, [])
    {session_key, mode, allow_hosts}
  end

  @impl true
  def call(conn, {session_key, mode, allow_hosts}) do
    csrf_token = dump_state_from_session(get_session(conn, session_key))
    load_state(conn.secret_key_base, csrf_token)

    conn =
      cond do
        verified_request?(conn, csrf_token, allow_hosts) ->
          conn

        mode == :clear_session ->
          conn |> configure_session(ignore: true) |> clear_session()

        mode == :exception ->
          raise InvalidCSRFTokenError

        true ->
          raise ArgumentError,
                "option :with should be one of :exception or :clear_session, got #{inspect(mode)}"
      end

    register_before_send(conn, &ensure_same_origin_and_csrf_token!(&1, session_key, csrf_token))
  end

  ## Verification

  defp verified_request?(conn, csrf_token, allow_hosts) do
    conn.method in @unprotected_methods ||
      valid_csrf_token?(conn, csrf_token, body_csrf_token(conn), allow_hosts) ||
      valid_csrf_token?(conn, csrf_token, header_csrf_token(conn), allow_hosts) ||
      skip_csrf_protection?(conn)
  end

  defp header_csrf_token(conn), do: List.first(get_req_header(conn, "x-csrf-token"))

  defp body_csrf_token(%{body_params: %{"_csrf_token" => csrf_token}}), do: csrf_token
  defp body_csrf_token(_), do: nil

  defp valid_csrf_token?(
         _conn,
         <<csrf_token::@encoded_token_size-binary>>,
         <<user_token::@double_encoded_token_size-binary, mask::@encoded_token_size-binary>>,
         _allow_hosts
       ) do
    valid_masked_token?(csrf_token, user_token, mask)
  end

  defp valid_csrf_token?(
         conn,
         <<csrf_token::@encoded_token_size-binary>>,
         <<@digest, _::binary>> = signed_user_token,
         allow_hosts
       ) do
    key = KeyGenerator.generate(conn.secret_key_base, csrf_token)

    case MessageVerifier.verify(signed_user_token, key) do
      {:ok, <<_::@encoded_token_size-binary, host::binary>>} ->
        if host == conn.host or Enum.any?(allow_hosts, &allowed_host?(&1, host)) do
          true
        else
          Logger.error("""
          Plug.CSRFProtection generated token for host #{inspect(host)} \
          but the host for the current request is #{inspect(conn.host)}. \
          See Plug.CSRFProtection documentation for more information.
          """)

          false
        end

      :error ->
        false
    end
  end

  defp valid_csrf_token?(_conn, _csrf_token, _user_token, _allowed_host), do: false

  # TODO: Remove the decode64 variant in future releases
  # as the tokens here are meant to be short-lived anyway.
  defp valid_masked_token?(csrf_token, user_token, mask) do
    with :error <- Base.url_decode64(user_token),
         :error <- Base.decode64(user_token) do
      false
    else
      {:ok, user_token} -> Plug.Crypto.masked_compare(csrf_token, user_token, mask)
    end
  end

  defp allowed_host?("." <> _ = allowed, host), do: String.ends_with?(host, allowed)
  defp allowed_host?(allowed, host), do: allowed == host

  ## Before send

  defp ensure_same_origin_and_csrf_token!(conn, session_key, csrf_token) do
    if cross_origin_js?(conn) do
      raise InvalidCrossOriginRequestError
    end

    ensure_csrf_token(conn, session_key, csrf_token)
  end

  defp cross_origin_js?(%Plug.Conn{method: "GET"} = conn),
    do: not skip_csrf_protection?(conn) and not xhr?(conn) and js_content_type?(conn)

  defp cross_origin_js?(%Plug.Conn{}), do: false

  defp js_content_type?(conn) do
    conn
    |> get_resp_header("content-type")
    |> Enum.any?(&String.starts_with?(&1, ~w(text/javascript application/javascript)))
  end

  defp xhr?(conn) do
    "XMLHttpRequest" in get_req_header(conn, "x-requested-with")
  end

  defp ensure_csrf_token(conn, session_key, csrf_token) do
    Process.delete(:plug_masked_csrf_token)

    case Process.delete(:plug_unmasked_csrf_token) do
      ^csrf_token -> conn
      nil -> conn
      :delete -> delete_session(conn, session_key)
      current -> put_session(conn, session_key, current)
    end
  end

  ## Helpers

  defp skip_csrf_protection?(%Plug.Conn{private: %{plug_skip_csrf_protection: true}}), do: true
  defp skip_csrf_protection?(%Plug.Conn{}), do: false

  defp mask(token) do
    mask = generate_token()
    Base.url_encode64(Plug.Crypto.mask(token, mask)) <> mask
  end

  defp unmasked_csrf_token do
    case Process.get(:plug_unmasked_csrf_token) do
      token when is_binary(token) ->
        token

      _ ->
        token = generate_token()
        Process.put(:plug_unmasked_csrf_token, token)
        token
    end
  end

  defp generate_token do
    Base.url_encode64(:crypto.strong_rand_bytes(@token_size))
  end
end
