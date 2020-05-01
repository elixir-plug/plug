defmodule Plug.BasicAuth do
  @moduledoc """
  Functionality for providing Basic HTTP authentication.

  It is recommended to only use this module in production
  if SSL is enabled and enforced. See `Plug.SSL` for more
  information.

  ## High-level usage

  If you have a single username and password, you can use
  the `basic_auth/2` plug:

      import Plug.BasicAuth
      plug :basic_auth, username: "hello", password: "secret"

  Or if you would rather put those in a config file:

      # lib/your_app.ex
      import Plug.BasicAuth
      plug :basic_auth, Application.compile_env(:my_app, :basic_auth)

      # config/config.exs
      config :my_app, :basic_auth, username: "hello", password: "secret"

  Once the user first accesses the page, the request will be denied
  with reason 401 and the request is halted. The browser will then
  prompt the user for username and password. If they match, then the
  request succeeds.

  Both approaches shown above rely on static configuration. In the next section
  we will explore using lower level API for a more dynamic solution where the
  credentials might be stored in a database, environment variables etc.

  ## Low-level usage

  If you want to provide your own authentication logic on top of Basic HTTP
  auth, you can use the low-level functions. As an example, we define `:auth`
  plug that extracts username and password from the request headers, compares
  them against the database, and either assigns a `:current_user` on success
  or responds with an error on failure.

      plug :auth

      defp auth(conn, _opts) do
        with {user, pass} <- Plug.BasicAuth.parse_basic_auth(conn),
             %User{} = user <- MyApp.Accounts.find_by_username_and_password(user, pass) do
          assign(conn, :current_user, user)
        else
          _ -> conn |> Plug.BasicAuth.request_basic_auth() |> halt()
        end
      end

  Keep in mind that:

    * The supplied `user` and `pass` may be empty strings;

    * If you are comparing the username and password with existing strings,
      do not use `==/2`. Use `Plug.Crypto.secure_compare/2` instead.

  """
  import Plug.Conn

  @doc """
  Higher level usage of Basic HTTP auth.

  See the module docs for examples.

  ## Options

    * `:username` - the expected username
    * `:password` - the expected password
    * `:realm` - the authentication realm. The value is not fully
      sanitized, so do not accept user input as the realm and use
      strings with only alphanumeric characters and space

  """
  def basic_auth(conn, options \\ []) do
    username = Keyword.fetch!(options, :username)
    password = Keyword.fetch!(options, :password)

    with {request_username, request_password} <- parse_basic_auth(conn),
         valid_username? = Plug.Crypto.secure_compare(username, request_username),
         valid_password? = Plug.Crypto.secure_compare(password, request_password),
         true <- valid_username? and valid_password? do
      conn
    else
      _ -> conn |> request_basic_auth(options) |> halt()
    end
  end

  @doc """
  Parses the request username and password from Basic HTTP auth.

  It returns either `{user, pass}` or `:error`. Note the username
  and password may be empty strings. When comparing the username
  and password with the expected values, be sure to use
  `Plug.Crypto.secure_compare/2`.

  See the module docs for examples.
  """
  def parse_basic_auth(conn) do
    with ["Basic " <> encoded_user_and_pass] <- get_req_header(conn, "authorization"),
         {:ok, decoded_user_and_pass} <- Base.decode64(encoded_user_and_pass),
         [user, pass] <- :binary.split(decoded_user_and_pass, ":") do
      {user, pass}
    else
      _ -> :error
    end
  end

  @doc """
  Encodes a basic authentication header.

  This can be used during tests:

      put_req_header(conn, "authorization", encode_basic_auth("hello", "world"))

  """
  def encode_basic_auth(user, pass) when is_binary(user) and is_binary(pass) do
    "Basic " <> Base.encode64("#{user}:#{pass}")
  end

  @doc """
  Requests basic authentication from the client.

  It sets the response to status 401 with "Unauthorized" as body.
  The response is not sent though (nor the connection is halted),
  allowing developers to further customize it.

  ## Options

    * `:realm` - the authentication realm. The value is not fully
      sanitized, so do not accept user input as the realm and use
      strings with only alphanumeric characters and space
  """
  def request_basic_auth(conn, options \\ []) when is_list(options) do
    realm = Keyword.get(options, :realm, "Application")
    escaped_realm = String.replace(realm, "\"", "")

    conn
    |> put_resp_header("www-authenticate", "Basic realm=\"#{escaped_realm}\"")
    |> resp(401, "Unauthorized")
  end
end
