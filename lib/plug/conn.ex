alias Plug.Conn.Unfetched

defmodule Plug.Conn do
  @moduledoc """
  The Plug connection.

  This module defines a struct and the main functions for working with
  requests and responses in an HTTP connection.

  Note request headers are normalized to lowercase and response
  headers are expected to have lowercase keys.

  ## Request fields

  These fields contain request information:

    * `host` - the requested host as a binary, example: `"www.example.com"`
    * `method` - the request method as a binary, example: `"GET"`
    * `path_info` - the path split into segments, example: `["hello", "world"]`
    * `script_name` - the initial portion of the URL's path that corresponds to
      the application routing, as segments, example: `["sub","app"]`
    * `request_path` - the requested path, example: `/trailing/and//double//slashes/`
    * `port` - the requested port as an integer, example: `80`
    * `remote_ip` - the IP of the client, example: `{151, 236, 219, 228}`. This field
      is meant to be overwritten by plugs that understand e.g. the `X-Forwarded-For`
      header or HAProxy's PROXY protocol. It defaults to peer's IP
    * `req_headers` - the request headers as a list, example: `[{"content-type", "text/plain"}]`.
      Note all headers will be downcased
    * `scheme` - the request scheme as an atom, example: `:http`
    * `query_string` - the request query string as a binary, example: `"foo=bar"`

  ## Fetchable fields

  Fetchable fields do not populate with request information until the corresponding
  prefixed 'fetch_' function retrieves them, e.g., the `fetch_cookies/2` function
  retrieves the `cookies` field.

  If you access these fields before fetching them, they will be returned as
  `Plug.Conn.Unfetched` structs.

    * `cookies`- the request cookies with the response cookies
    * `body_params` - the request body params, populated through a `Plug.Parsers` parser.
    * `query_params` - the request query params, populated through `fetch_query_params/2`
    * `path_params` - the request path params, populated by routers such as `Plug.Router`
    * `params` - the request params, the result of merging the `:path_params` on top of
       `:body_params` on top of `:query_params`
    * `req_cookies` - the request cookies (without the response ones)

  ## Session vs Assigns

  HTTP is stateless.

  This means that a server begins each request cycle with no knowledge about
  the client except the request itself. Its response may include one or more
  `"Set-Cookie"` headers, asking the client to send that value back in a
  `"Cookie"` header on subsequent requests.

  This is the basis for stateful interactions with a client, so that the server
  can remember the client's name, the contents of their shopping cart, and so on.

  In `Plug`, a "session" is a place to store data that persists from one request
  to the next. Typically, this data is stored in a cookie using `Plug.Session.COOKIE`.

  A minimal approach would be to store only a user's id in the session, then
  use that during the request cycle to look up other information (in a database
  or elsewhere).

  More can be stored in a session cookie, but be careful: this makes requests
  and responses heavier, and clients may reject cookies beyond a certain size.
  Also, session cookie are not shared between a user's different browsers or devices.

  If the session is stored elsewhere, such as with `Plug.Session.ETS`, session
  data lookup still needs a key, e.g., a user's id. Unlike session data, `assigns`
  data fields only last a single request.

  A typical use case would be for an authentication plug to look up a user by id
  and keep the state of the user's credentials by storing them in `assigns`.
  Other plugs will then also have access through the `assigns` storage. This is
  an important point because the session data disappears on the next request.

  To summarize: `assigns` is for storing data to be accessed during the current
  request, and the session is for storing data to be accessed in subsequent
  requests.

  ## Response fields

  These fields contain response information:

    * `resp_body` - the response body is an empty string by default. It is set
      to nil after the response is sent, except for test connections. The response
      charset defaults to "utf-8".
    * `resp_cookies` - the response cookies with their name and options
    * `resp_headers` - the response headers as a list of tuples, `cache-control`
      is set to `"max-age=0, private, must-revalidate"` by default.
      Note: Use all lowercase for response headers.
    * `status` - the response status

  ## Connection fields

    * `assigns` - shared user data as a map
    * `owner` - the Elixir process that owns the connection
    * `halted` - the boolean status on whether the pipeline was halted
    * `secret_key_base` - a secret key used to verify and encrypt cookies.
      These features require manual field setup. Data must be kept in the
      connection and never used directly. Always use `Plug.Crypto.KeyGenerator.generate/3`
      to derive keys from it.
    * `state` - the connection state

  The connection state is used to track the connection lifecycle. It starts as
  `:unset` but is changed to `:set` (via `resp/3`) or `:set_chunked`
  (used only for `before_send` callbacks by `send_chunked/2`) or `:file`
  (when invoked via `send_file/3`). Its final result is `:sent`, `:file`, `:chunked`
  or `:upgraded` depending on the response model.

  ## Private fields

  These fields are reserved for libraries/framework usage.

    * `adapter` - holds the adapter information in a tuple
    * `private` - shared library data as a map

  ## Custom status codes

  `Plug` allows status codes to be overridden or added and allow new codes not directly
  specified by `Plug` or its adapters. The `:plug` application's Mix config can add or
  override a status code.

  For example, the config below overrides the default 404 reason phrase ("Not Found")
  and adds a new 998 status code:

      config :plug, :statuses, %{
        404 => "Actually This Was Found",
        998 => "Not An RFC Status Code"
      }

  Dependency-specific config changes are not automatically recompiled. Recompile `Plug`
  for the changes to take place. The command below recompiles `Plug`:

      mix deps.clean --build plug

  A corresponding atom is inflected from each status code reason phrase. In many functions,
  these atoms can stand in for the status code. For example, with the above configuration,
  the following will work:

      put_status(conn, :not_found)                     # 404
      put_status(conn, :actually_this_was_found)       # 404
      put_status(conn, :not_an_rfc_status_code)        # 998

  The `:not_found` atom can still be used to set the 404 status even though the 404 status code
  reason phrase was overwritten. The new atom `:actually_this_was_found`, inflected from the
  reason phrase "Actually This Was Found", can also be used to set the 404 status code.

  ## Protocol Upgrades

  `Plug.Conn.upgrade_adapter/3` provides basic support for protocol upgrades and facilitates
  connection upgrades to protocols such as WebSockets. As the name suggests, this functionality
  is adapter-dependent. Protocol upgrade functionality requires explicit coordination between
  a `Plug` application and the underlying adapter.

  `Plug` upgrade-related functionality only provides the possibility for the `Plug` application
  to request protocol upgrades from the underlying adapter. See `upgrade_adapter/3` documentation.
  """

  @type adapter :: {module, term}
  @type assigns :: %{optional(atom) => any}
  @type body :: iodata
  @type req_cookies :: %{optional(binary) => binary}
  @type cookies :: %{optional(binary) => term}
  @type halted :: boolean
  @type headers :: [{binary, binary}]
  @type host :: binary
  @type int_status :: non_neg_integer | nil
  @type owner :: pid
  @type method :: binary
  @type query_param :: binary | %{optional(binary) => query_param} | [query_param]
  @type query_params :: %{optional(binary) => query_param}
  @type params :: %{optional(binary) => term}
  @type port_number :: :inet.port_number()
  @type query_string :: String.t()
  @type resp_cookies :: %{optional(binary) => map()}
  @type scheme :: :http | :https
  @type secret_key_base :: binary | nil
  @type segments :: [binary]
  @type state :: :unset | :set | :set_chunked | :set_file | :file | :chunked | :sent | :upgraded
  @type status :: atom | int_status

  @type t :: %__MODULE__{
          adapter: adapter,
          assigns: assigns,
          body_params: params | Unfetched.t(),
          cookies: cookies | Unfetched.t(),
          halted: halted,
          host: host,
          method: method,
          owner: owner,
          params: params | Unfetched.t(),
          path_info: segments,
          path_params: query_params,
          port: :inet.port_number(),
          private: assigns,
          query_params: query_params | Unfetched.t(),
          query_string: query_string,
          remote_ip: :inet.ip_address(),
          req_cookies: req_cookies | Unfetched.t(),
          req_headers: headers,
          request_path: binary,
          resp_body: body | nil,
          resp_cookies: resp_cookies,
          resp_headers: headers,
          scheme: scheme,
          script_name: segments,
          secret_key_base: secret_key_base,
          state: state,
          status: int_status
        }

  defstruct adapter: {Plug.MissingAdapter, nil},
            assigns: %{},
            body_params: %Unfetched{aspect: :body_params},
            cookies: %Unfetched{aspect: :cookies},
            halted: false,
            host: "www.example.com",
            method: "GET",
            owner: nil,
            params: %Unfetched{aspect: :params},
            path_info: [],
            path_params: %{},
            port: 0,
            private: %{},
            query_params: %Unfetched{aspect: :query_params},
            query_string: "",
            remote_ip: nil,
            req_cookies: %Unfetched{aspect: :cookies},
            req_headers: [],
            request_path: "",
            resp_body: nil,
            resp_cookies: %{},
            resp_headers: [{"cache-control", "max-age=0, private, must-revalidate"}],
            scheme: :http,
            script_name: [],
            secret_key_base: nil,
            state: :unset,
            status: nil

  defmodule NotSentError do
    defexception message: "a response was neither set nor sent from the connection"

    @moduledoc """
    Error raised when no response is sent in a request
    """
  end

  defmodule AlreadySentError do
    defexception message: "the response was already sent"

    @moduledoc """
    Error raised when trying to modify or send an already sent response
    """
  end

  defmodule CookieOverflowError do
    defexception message: "cookie exceeds maximum size of 4096 bytes"

    @moduledoc """
    Error raised when the cookie exceeds the maximum size of 4096 bytes.
    """
  end

  defmodule InvalidHeaderError do
    defexception message: "header is invalid"

    @moduledoc ~S"""
    Error raised when trying to send a header that has errors, for example:

      * the header key contains uppercase chars
      * the header value contains newlines \n
    """
  end

  defmodule InvalidQueryError do
    @moduledoc """
    Raised when the request string is malformed, for example:

      * the query has bad utf-8 encoding
      * the query fails to www-form decode
    """

    defexception message: "query string is invalid", plug_status: 400
  end

  alias Plug.Conn
  @epoch {{1970, 1, 1}, {0, 0, 0}}
  @already_sent {:plug_conn, :sent}
  @unsent [:unset, :set, :set_chunked, :set_file]

  @doc """
  Assigns a value to a key in the connection.

  The `assigns` storage is meant to be used to store values in the connection
  so that other plugs in your plug pipeline can access them. The `assigns` storage
  is a map.

  ## Examples

      iex> conn.assigns[:hello]
      nil
      iex> conn = assign(conn, :hello, :world)
      iex> conn.assigns[:hello]
      :world

  """
  @spec assign(t, atom, term) :: t
  def assign(%Conn{assigns: assigns} = conn, key, value) when is_atom(key) do
    %{conn | assigns: Map.put(assigns, key, value)}
  end

  @doc """
  Assigns multiple values to keys in the connection.

  Equivalent to multiple calls to `assign/3`.

  ## Examples

      iex> conn.assigns[:hello]
      nil
      iex> conn = merge_assigns(conn, hello: :world)
      iex> conn.assigns[:hello]
      :world

  """
  @spec merge_assigns(t, Enumerable.t()) :: t
  def merge_assigns(%Conn{assigns: assigns} = conn, new) do
    %{conn | assigns: Enum.into(new, assigns)}
  end

  @doc false
  @deprecated "Call assign + Task.async instead"
  def async_assign(%Conn{} = conn, key, fun) when is_atom(key) and is_function(fun, 0) do
    assign(conn, key, Task.async(fun))
  end

  @doc false
  @deprecated "Fetch the assign and call Task.await instead"
  def await_assign(%Conn{} = conn, key, timeout \\ 5000) when is_atom(key) do
    task = Map.fetch!(conn.assigns, key)
    assign(conn, key, Task.await(task, timeout))
  end

  @doc """
  Assigns a new **private** key and value in the connection.

  This storage is meant to be used by libraries and frameworks to avoid writing
  to the user storage (the `:assigns` field). It is recommended for
  libraries/frameworks to prefix the keys with the library name.

  For example, if a plug called `my_plug` needs to store a `:hello`
  key, it would store it as `:my_plug_hello`:

      iex> conn.private[:my_plug_hello]
      nil
      iex> conn = put_private(conn, :my_plug_hello, :world)
      iex> conn.private[:my_plug_hello]
      :world

  """
  @spec put_private(t, atom, term) :: t
  def put_private(%Conn{private: private} = conn, key, value) when is_atom(key) do
    %{conn | private: Map.put(private, key, value)}
  end

  @doc """
  Assigns multiple **private** keys and values in the connection.

  Equivalent to multiple `put_private/3` calls.

  ## Examples

      iex> conn.private[:my_plug_hello]
      nil
      iex> conn = merge_private(conn, my_plug_hello: :world)
      iex> conn.private[:my_plug_hello]
      :world

  """
  @spec merge_private(t, Enumerable.t()) :: t
  def merge_private(%Conn{private: private} = conn, new) do
    %{conn | private: Enum.into(new, private)}
  end

  @doc """
  Stores the given status code in the connection.

  The status code can be `nil`, an integer, or an atom. The list of allowed
  atoms is available in `Plug.Conn.Status`.

  Raises a `Plug.Conn.AlreadySentError` if the connection has already been
  `:sent`, `:chunked` or `:upgraded`.

  ## Examples

      Plug.Conn.put_status(conn, :not_found)
      Plug.Conn.put_status(conn, 200)

  """
  @spec put_status(t, status) :: t
  def put_status(%Conn{state: state}, _status) when state not in @unsent do
    raise AlreadySentError
  end

  def put_status(%Conn{} = conn, nil), do: %{conn | status: nil}
  def put_status(%Conn{} = conn, status), do: %{conn | status: Plug.Conn.Status.code(status)}

  @doc """
  Sends a response to the client.

  It expects the connection state to be `:set`, otherwise raises an
  `ArgumentError` for `:unset` connections or a `Plug.Conn.AlreadySentError` for
  already `:sent`, `:chunked` or `:upgraded` connections.

  At the end sets the connection state to `:sent`.

  Note that this function does not halt the connection, so if
  subsequent plugs try to send another response, it will error out.
  Use `halt/1` after this function if you want to halt the plug pipeline.

  ## Examples

      conn
      |> Plug.Conn.resp(404, "Not found")
      |> Plug.Conn.send_resp()

  """
  @spec send_resp(t) :: t | no_return
  def send_resp(conn)

  def send_resp(%Conn{state: :unset}) do
    raise ArgumentError, "cannot send a response that was not set"
  end

  def send_resp(%Conn{adapter: {adapter, payload}, state: :set, owner: owner} = conn) do
    conn = run_before_send(conn, :set)

    {:ok, body, payload} =
      adapter.send_resp(payload, conn.status, conn.resp_headers, conn.resp_body)

    send(owner, @already_sent)
    %{conn | adapter: {adapter, payload}, resp_body: body, state: :sent}
  end

  def send_resp(%Conn{}) do
    raise AlreadySentError
  end

  @doc """
  Sends a file as the response body with the given `status`
  and optionally starting at the given offset until the given length.

  If available, the file is sent directly over the socket using
  the operating system `sendfile` operation.

  It expects a connection that has not been `:sent`, `:chunked` or `:upgraded` yet and sets its
  state to `:file` afterwards. Otherwise raises `Plug.Conn.AlreadySentError`.

  ## Examples

      Plug.Conn.send_file(conn, 200, "README.md")

  """
  @spec send_file(t, status, filename :: binary, offset :: integer, length :: integer | :all) ::
          t | no_return
  def send_file(conn, status, file, offset \\ 0, length \\ :all)

  def send_file(%Conn{state: state}, status, _file, _offset, _length)
      when state not in @unsent do
    _ = Plug.Conn.Status.code(status)
    raise AlreadySentError
  end

  def send_file(
        %Conn{adapter: {adapter, payload}, owner: owner} = conn,
        status,
        file,
        offset,
        length
      )
      when is_binary(file) do
    if file =~ "\0" do
      raise ArgumentError, "cannot send_file/5 with null byte"
    end

    conn =
      run_before_send(%{conn | status: Plug.Conn.Status.code(status), resp_body: nil}, :set_file)

    {:ok, body, payload} =
      adapter.send_file(payload, conn.status, conn.resp_headers, file, offset, length)

    send(owner, @already_sent)
    %{conn | adapter: {adapter, payload}, state: :file, resp_body: body}
  end

  @doc """
  Sends the response headers as a chunked response.

  It expects a connection that has not been `:sent` or `:upgraded` yet and sets its
  state to `:chunked` afterwards. Otherwise, raises `Plug.Conn.AlreadySentError`.
  After `send_chunked/2` is called, chunks can be sent to the client via
  the `chunk/2` function.

  HTTP/2 does not support chunking and will instead stream the response without a
  transfer encoding. When using HTTP/1.1, the Cowboy adapter will stream the response
  instead of emitting chunks if the `content-length` header has been set before calling
  `send_chunked/2`.
  """
  @spec send_chunked(t, status) :: t | no_return
  def send_chunked(%Conn{state: state}, status)
      when state not in @unsent do
    _ = Plug.Conn.Status.code(status)
    raise AlreadySentError
  end

  def send_chunked(%Conn{adapter: {adapter, payload}, owner: owner} = conn, status) do
    conn = %{conn | status: Plug.Conn.Status.code(status), resp_body: nil}
    conn = run_before_send(conn, :set_chunked)
    {:ok, body, payload} = adapter.send_chunked(payload, conn.status, conn.resp_headers)
    send(owner, @already_sent)
    %{conn | adapter: {adapter, payload}, state: :chunked, resp_body: body}
  end

  @doc """
  Sends a chunk as part of a chunked response.

  It expects a connection with state `:chunked` as set by
  `send_chunked/2`. It returns `{:ok, conn}` in case of success,
  otherwise `{:error, reason}`.

  To stream data use `Enum.reduce_while/3` instead of `Enum.into/2`.
  `Enum.reduce_while/3` allows aborting the execution if `chunk/2` fails to
  deliver the chunk of data.

  ## Example

      Enum.reduce_while(~w(each chunk as a word), conn, fn (chunk, conn) ->
        case Plug.Conn.chunk(conn, chunk) do
          {:ok, conn} ->
            {:cont, conn}
          {:error, :closed} ->
            {:halt, conn}
        end
      end)

  """
  @spec chunk(t, body) :: {:ok, t} | {:error, term} | no_return
  def chunk(%Conn{adapter: {adapter, payload}, state: :chunked} = conn, chunk) do
    if iodata_empty?(chunk) do
      {:ok, conn}
    else
      case adapter.chunk(payload, chunk) do
        :ok -> {:ok, conn}
        {:ok, body, payload} -> {:ok, %{conn | resp_body: body, adapter: {adapter, payload}}}
        {:error, _} = error -> error
      end
    end
  end

  def chunk(%Conn{}, chunk) when is_binary(chunk) or is_list(chunk) do
    raise ArgumentError,
          "chunk/2 expects a chunked response. Please ensure " <>
            "you have called send_chunked/2 before you send a chunk"
  end

  defp iodata_empty?(""), do: true
  defp iodata_empty?([]), do: true
  defp iodata_empty?([head | tail]), do: iodata_empty?(head) and iodata_empty?(tail)
  defp iodata_empty?(_), do: false

  @doc """
  Sends a response with the given status and body.

  This is equivalent to setting the status and the body and then
  calling `send_resp/1`.

  Note that this function does not halt the connection, so if
  subsequent plugs try to send another response, it will error out.
  Use `halt/1` after this function if you want to halt the plug pipeline.

  ## Examples

      Plug.Conn.send_resp(conn, 404, "Not found")

  """
  @spec send_resp(t, status, body) :: t | no_return
  def send_resp(%Conn{} = conn, status, body) do
    conn |> resp(status, body) |> send_resp()
  end

  @doc """
  Sets the response to the given `status` and `body`.

  It sets the connection state to `:set` (if not already `:set`)
  and raises `Plug.Conn.AlreadySentError` if it was already `:sent`, `:chunked` or `:upgraded`.

  If you also want to send the response, use `send_resp/1` after this
  or use `send_resp/3`.

  The status can be an integer, an atom, or `nil`. See `Plug.Conn.Status`
  for more information.

  ## Examples

      Plug.Conn.resp(conn, 404, "Not found")

  """
  @spec resp(t, status, body) :: t
  def resp(%Conn{state: state}, status, _body)
      when state not in @unsent do
    _ = Plug.Conn.Status.code(status)
    raise AlreadySentError
  end

  def resp(%Conn{}, _status, nil) do
    raise ArgumentError, "response body cannot be set to nil"
  end

  def resp(%Conn{} = conn, status, body)
      when is_binary(body) or is_list(body) do
    %{conn | status: Plug.Conn.Status.code(status), resp_body: body, state: :set}
  end

  @doc """
  Returns the request peer data if one is present.
  """
  @spec get_peer_data(t) :: Plug.Conn.Adapter.peer_data()
  def get_peer_data(%Conn{adapter: {adapter, payload}}) do
    adapter.get_peer_data(payload)
  end

  @doc """
  Returns the HTTP protocol and version.

  ## Examples

      iex> get_http_protocol(conn)
      :"HTTP/1.1"

  """
  @spec get_http_protocol(t) :: Plug.Conn.Adapter.http_protocol()
  def get_http_protocol(%Conn{adapter: {adapter, payload}}) do
    adapter.get_http_protocol(payload)
  end

  @doc """
  Returns the values of the request header specified by `key`.

  ## Examples

      iex> get_req_header(conn, "accept")
      ["application/json"]

  """
  @spec get_req_header(t, binary) :: [binary]
  def get_req_header(%Conn{req_headers: headers}, key) when is_binary(key) do
    for {^key, value} <- headers, do: value
  end

  @doc ~S"""
  Prepends the list of headers to the connection request headers.

  Similar to `put_req_header` this functions adds a new request header
  (`key`) but rather than replacing the existing one it prepends another
  header with the same `key`.

  The "host" header will be overridden by `conn.host` and should not be set
  with this method. Instead, do `%Plug.Conn{conn | host: value}`.

  Because header keys are case-insensitive in both HTTP/1.1 and HTTP/2,
  it is recommended for header keys to be in lowercase, to avoid sending
  duplicate keys in a request.
  Additionally, requests with mixed-case headers served over HTTP/2 are not
  considered valid by common clients, resulting in dropped requests.
  As a convenience, when using the `Plug.Adapters.Conn.Test` adapter, any
  headers that aren't lowercase will raise a `Plug.Conn.InvalidHeaderError`.

  Raises a `Plug.Conn.AlreadySentError` if the connection has already been
  `:sent`, `:chunked` or `:upgraded`.

  ## Examples

      Plug.Conn.prepend_req_headers(conn, [{"accept", "application/json"}])

  """
  @spec prepend_req_headers(t, headers) :: t
  def prepend_req_headers(conn, headers)

  def prepend_req_headers(%Conn{state: state}, _headers) when state not in @unsent do
    raise AlreadySentError
  end

  def prepend_req_headers(%Conn{adapter: adapter, req_headers: req_headers} = conn, headers)
      when is_list(headers) do
    for {key, _value} <- headers do
      validate_req_header!(adapter, key)
    end

    %{conn | req_headers: headers ++ req_headers}
  end

  @doc """
  Merges a series of request headers into the connection.

  The "host" header will be overridden by `conn.host` and should not be set
  with this method. Instead, do `%Plug.Conn{conn | host: value}`.

  Because header keys are case-insensitive in both HTTP/1.1 and HTTP/2,
  it is recommended for header keys to be in lowercase, to avoid sending
  duplicate keys in a request.
  Additionally, requests with mixed-case headers served over HTTP/2 are not
  considered valid by common clients, resulting in dropped requests.
  As a convenience, when using the `Plug.Adapters.Conn.Test` adapter, any
  headers that aren't lowercase will raise a `Plug.Conn.InvalidHeaderError`.

  ## Example

      Plug.Conn.merge_req_headers(conn, [{"accept", "text/plain"}, {"X-1337", "5P34K"}])

  """
  @spec merge_req_headers(t, Enum.t()) :: t
  def merge_req_headers(conn, headers)

  def merge_req_headers(%Conn{state: state}, _headers) when state not in @unsent do
    raise AlreadySentError
  end

  def merge_req_headers(conn, headers) when headers == %{} do
    conn
  end

  def merge_req_headers(%Conn{req_headers: current, adapter: adapter} = conn, headers) do
    headers =
      Enum.reduce(headers, current, fn {key, value}, acc
                                       when is_binary(key) and is_binary(value) ->
        validate_req_header!(adapter, key)
        List.keystore(acc, key, 0, {key, value})
      end)

    %{conn | req_headers: headers}
  end

  @doc """
  Adds a new request header (`key`) if not present, otherwise replaces the
  previous value of that header with `value`.

  The "host" header will be overridden by `conn.host` and should not be set
  with this method. Instead, do `%Plug.Conn{conn | host: value}`.

  Because header keys are case-insensitive in both HTTP/1.1 and HTTP/2,
  it is recommended for header keys to be in lowercase, to avoid sending
  duplicate keys in a request.
  Additionally, requests with mixed-case headers served over HTTP/2 are not
  considered valid by common clients, resulting in dropped requests.
  As a convenience, when using the `Plug.Adapters.Conn.Test` adapter, any
  headers that aren't lowercase will raise a `Plug.Conn.InvalidHeaderError`.

  Raises a `Plug.Conn.AlreadySentError` if the connection has already been
  `:sent`, `:chunked` or `:upgraded`.

  ## Examples

      Plug.Conn.put_req_header(conn, "accept", "application/json")

  """
  @spec put_req_header(t, binary, binary) :: t
  def put_req_header(conn, key, value)

  def put_req_header(%Conn{state: state}, _key, _value) when state not in @unsent do
    raise AlreadySentError
  end

  def put_req_header(%Conn{adapter: adapter, req_headers: headers} = conn, key, value)
      when is_binary(key) and is_binary(value) do
    validate_req_header!(adapter, key)
    %{conn | req_headers: List.keystore(headers, key, 0, {key, value})}
  end

  @doc """
  Deletes a request header if present.

  Raises a `Plug.Conn.AlreadySentError` if the connection has already been
  `:sent`, `:chunked` or `:upgraded`.

  ## Examples

      Plug.Conn.delete_req_header(conn, "content-type")

  """
  @spec delete_req_header(t, binary) :: t
  def delete_req_header(conn, key)

  def delete_req_header(%Conn{state: state}, _key) when state not in @unsent do
    raise AlreadySentError
  end

  def delete_req_header(%Conn{req_headers: headers} = conn, key)
      when is_binary(key) do
    %{conn | req_headers: List.keydelete(headers, key, 0)}
  end

  @doc """
  Updates a request header if present, otherwise it sets it to an initial
  value.

  Raises a `Plug.Conn.AlreadySentError` if the connection has already been
  `:sent`, `:chunked` or `:upgraded`.

  Only the first value of the header `key` is updated if present.

  ## Examples

      Plug.Conn.update_req_header(
        conn,
        "accept",
        "application/json; charset=utf-8",
        &(&1 <> "; charset=utf-8")
      )

  """
  @spec update_req_header(t, binary, binary, (binary -> binary)) :: t
  def update_req_header(conn, key, initial, fun)

  def update_req_header(%Conn{state: state}, _key, _initial, _fun) when state not in @unsent do
    raise AlreadySentError
  end

  def update_req_header(%Conn{} = conn, key, initial, fun)
      when is_binary(key) and is_binary(initial) and is_function(fun, 1) do
    case get_req_header(conn, key) do
      [] -> put_req_header(conn, key, initial)
      [current | _] -> put_req_header(conn, key, fun.(current))
    end
  end

  @doc """
  Returns the values of the response header specified by `key`.

  ## Examples

      iex> conn = %{conn | resp_headers: [{"content-type", "text/plain"}]}
      iex> get_resp_header(conn, "content-type")
      ["text/plain"]

  """
  @spec get_resp_header(t, binary) :: [binary]
  def get_resp_header(%Conn{resp_headers: headers}, key) when is_binary(key) do
    for {^key, value} <- headers, do: value
  end

  @doc ~S"""
  Adds a new response header (`key`) if not present, otherwise replaces the
  previous value of that header with `value`.

  Because header keys are case-insensitive in both HTTP/1.1 and HTTP/2,
  it is recommended for header keys to be in lowercase, to avoid sending
  duplicate keys in a request.
  Additionally, responses with mixed-case headers served over HTTP/2 are not
  considered valid by common clients, resulting in dropped responses.
  As a convenience, when using the `Plug.Adapters.Conn.Test` adapter, any
  headers that aren't lowercase will raise a `Plug.Conn.InvalidHeaderError`.

  Raises a `Plug.Conn.AlreadySentError` if the connection has already been
  `:sent`, `:chunked` or `:upgraded`.

  Raises a `Plug.Conn.InvalidHeaderError` if the header value contains control
  feed (`\r`) or newline (`\n`) characters.

  ## Examples

      Plug.Conn.put_resp_header(conn, "content-type", "application/json")

  """
  @spec put_resp_header(t, binary, binary) :: t
  def put_resp_header(%Conn{state: state}, _key, _value) when state not in @unsent do
    raise AlreadySentError
  end

  def put_resp_header(%Conn{adapter: adapter, resp_headers: headers} = conn, key, value)
      when is_binary(key) and is_binary(value) do
    validate_header_key_normalized_if_test!(adapter, key)
    validate_header_key_value!(key, value)
    %{conn | resp_headers: List.keystore(headers, key, 0, {key, value})}
  end

  @doc ~S"""
  Prepends the list of headers to the connection response headers.

  Similar to `put_resp_header` this functions adds a new response header
  (`key`) but rather than replacing the existing one it prepends another header
  with the same `key`.

  It is recommended for header keys to be in lowercase, to avoid sending
  duplicate keys in a request.
  Additionally, responses with mixed-case headers served over HTTP/2 are not
  considered valid by common clients, resulting in dropped responses.
  As a convenience, when using the `Plug.Adapters.Conn.Test` adapter, any
  headers that aren't lowercase will raise a `Plug.Conn.InvalidHeaderError`.

  Raises a `Plug.Conn.AlreadySentError` if the connection has already been
  `:sent`, `:chunked` or `:upgraded`.

  Raises a `Plug.Conn.InvalidHeaderError` if the header value contains control
  feed (`\r`) or newline (`\n`) characters.

  ## Examples

      Plug.Conn.prepend_resp_headers(conn, [{"content-type", "application/json"}])

  """
  @spec prepend_resp_headers(t, headers) :: t
  def prepend_resp_headers(conn, headers)

  def prepend_resp_headers(%Conn{state: state}, _headers) when state not in @unsent do
    raise AlreadySentError
  end

  def prepend_resp_headers(%Conn{adapter: adapter, resp_headers: resp_headers} = conn, headers)
      when is_list(headers) do
    for {key, value} <- headers do
      validate_header_key_normalized_if_test!(adapter, key)
      validate_header_key_value!(key, value)
    end

    %{conn | resp_headers: headers ++ resp_headers}
  end

  @doc """
  Merges a series of response headers into the connection.

  It is recommended for header keys to be in lowercase, to avoid sending
  duplicate keys in a request.
  Additionally, responses with mixed-case headers served over HTTP/2 are not
  considered valid by common clients, resulting in dropped responses.
  As a convenience, when using the `Plug.Adapters.Conn.Test` adapter, any
  headers that aren't lowercase will raise a `Plug.Conn.InvalidHeaderError`.

  ## Example

      Plug.Conn.merge_resp_headers(conn, [{"content-type", "text/plain"}, {"X-1337", "5P34K"}])

  """
  @spec merge_resp_headers(t, Enum.t()) :: t
  def merge_resp_headers(conn, headers)

  def merge_resp_headers(%Conn{state: state}, _headers) when state not in @unsent do
    raise AlreadySentError
  end

  def merge_resp_headers(conn, headers) when headers == %{} do
    conn
  end

  def merge_resp_headers(%Conn{resp_headers: current, adapter: adapter} = conn, headers) do
    headers =
      Enum.reduce(headers, current, fn {key, value}, acc
                                       when is_binary(key) and is_binary(value) ->
        validate_header_key_normalized_if_test!(adapter, key)
        validate_header_key_value!(key, value)
        List.keystore(acc, key, 0, {key, value})
      end)

    %{conn | resp_headers: headers}
  end

  @doc """
  Deletes a response header if present.

  Raises a `Plug.Conn.AlreadySentError` if the connection has already been
  `:sent`, `:chunked` or `:upgraded`.

  ## Examples

      Plug.Conn.delete_resp_header(conn, "content-type")

  """
  @spec delete_resp_header(t, binary) :: t
  def delete_resp_header(%Conn{state: state}, _key) when state not in @unsent do
    raise AlreadySentError
  end

  def delete_resp_header(%Conn{resp_headers: headers} = conn, key)
      when is_binary(key) do
    %{conn | resp_headers: List.keydelete(headers, key, 0)}
  end

  @doc """
  Updates a response header if present, otherwise it sets it to an initial
  value.

  Raises a `Plug.Conn.AlreadySentError` if the connection has already been
  `:sent`, `:chunked` or `:upgraded`.

  Only the first value of the header `key` is updated if present.

  ## Examples

      Plug.Conn.update_resp_header(
        conn,
        "content-type",
        "application/json; charset=utf-8",
        &(&1 <> "; charset=utf-8")
      )

  """
  @spec update_resp_header(t, binary, binary, (binary -> binary)) :: t
  def update_resp_header(conn, key, initial, fun)

  def update_resp_header(%Conn{state: state}, _key, _initial, _fun) when state not in @unsent do
    raise AlreadySentError
  end

  def update_resp_header(%Conn{} = conn, key, initial, fun)
      when is_binary(key) and is_binary(initial) and is_function(fun, 1) do
    case get_resp_header(conn, key) do
      [] -> put_resp_header(conn, key, initial)
      [current | _] -> put_resp_header(conn, key, fun.(current))
    end
  end

  @doc """
  Sets the value of the `"content-type"` response header taking into account the
  `charset`.

  If `charset` is `nil`, the value of the `"content-type"` response header won't
  specify a charset.

  ## Examples

      iex> conn = put_resp_content_type(conn, "application/json")
      iex> get_resp_header(conn, "content-type")
      ["application/json; charset=utf-8"]

  """
  @spec put_resp_content_type(t, binary, binary | nil) :: t
  def put_resp_content_type(conn, content_type, charset \\ "utf-8")

  def put_resp_content_type(conn, content_type, nil) when is_binary(content_type) do
    put_resp_header(conn, "content-type", content_type)
  end

  def put_resp_content_type(conn, content_type, charset)
      when is_binary(content_type) and is_binary(charset) do
    put_resp_header(conn, "content-type", "#{content_type}; charset=#{charset}")
  end

  @doc """
  Fetches query parameters from the query string.

  Params are decoded as `"x-www-form-urlencoded"` in which key/value pairs
  are separated by `&` and keys are separated from values by `=`.

  This function does not fetch parameters from the body. To fetch
  parameters from the body, use the `Plug.Parsers` plug.

  ## Options

    * `:length` - the maximum query string length. Defaults to `1_000_000` bytes.
      Keep in mind the webserver you are using may have a more strict limit. For
      example, for the Cowboy webserver, [please read](https://hexdocs.pm/plug_cowboy/Plug.Cowboy.html#module-safety-limits).

    * `:validate_utf8` - boolean that tells whether or not to validate the keys and
      values of the decoded query string are UTF-8 encoded. Defaults to `true`.

  """
  @spec fetch_query_params(t, Keyword.t()) :: t
  def fetch_query_params(conn, opts \\ [])

  def fetch_query_params(%Conn{query_params: %Unfetched{}} = conn, opts) do
    %{params: params, query_string: query_string} = conn
    length = Keyword.get(opts, :length, 1_000_000)

    if byte_size(query_string) > length do
      raise InvalidQueryError,
        message:
          "maximum query string length is #{length}, got a query with #{byte_size(query_string)} bytes",
        plug_status: 414
    end

    query_params =
      Plug.Conn.Query.decode(
        query_string,
        %{},
        Plug.Conn.InvalidQueryError,
        Keyword.get(opts, :validate_utf8, true)
      )

    case params do
      %Unfetched{} -> %{conn | query_params: query_params, params: query_params}
      %{} -> %{conn | query_params: query_params, params: Map.merge(query_params, params)}
    end
  end

  def fetch_query_params(%Conn{} = conn, _opts) do
    conn
  end

  @doc """
  Reads the request body.

  This function reads a chunk of the request body up to a given length (specified
  by the `:length` option). If there is more data to be read, then
  `{:more, partial_body, conn}` is returned. Otherwise `{:ok, body, conn}` is
  returned. In case of an error reading the socket, `{:error, reason}` is
  returned as per `:gen_tcp.recv/2`.

  Like all functions in this module, the `conn` returned by `read_body` must
  be passed to the next stage of your pipeline and should not be ignored.

  In order to, for instance, support slower clients you can tune the
  `:read_length` and `:read_timeout` options. These specify how much time should
  be allowed to pass for each read from the underlying socket.

  Because the request body can be of any size, reading the body will only
  work once, as `Plug` will not cache the result of these operations. If you
  need to access the body multiple times, it is your responsibility to store
  it. Finally keep in mind some plugs like `Plug.Parsers` may read the body,
  so the body may be unavailable after being accessed by such plugs.

  This function is able to handle both chunked and identity transfer-encoding
  by default.

  ## Options

    * `:length` - sets the maximum number of bytes to read from the body on
      every call, defaults to `8_000_000` bytes
    * `:read_length` - sets the amount of bytes to read at one time from the
      underlying socket to fill the chunk, defaults to `1_000_000` bytes
    * `:read_timeout` - sets the timeout for each socket read, defaults to
      `15_000` milliseconds

  The values above are not meant to be exact. For example, setting the
  length to `8_000_000` may end up reading some hundred bytes more from
  the socket until we halt.

  ## Examples

      {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_000_000)

  """
  @spec read_body(t, Keyword.t()) ::
          {:ok, binary, t}
          | {:more, binary, t}
          | {:error, term}
  def read_body(%Conn{adapter: {adapter, state}} = conn, opts \\ []) do
    case adapter.read_req_body(state, opts) do
      {:ok, data, state} ->
        {:ok, data, %{conn | adapter: {adapter, state}}}

      {:more, data, state} ->
        {:more, data, %{conn | adapter: {adapter, state}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Reads the headers of a multipart request.

  It returns `{:ok, headers, conn}` with the headers or
  `{:done, conn}` if there are no more parts.

  Once `read_part_headers/2` is invoked, you may call
  `read_part_body/2` to read the body associated to the headers.
  If `read_part_headers/2` is called instead, the body is automatically
  skipped until the next part headers.

  ## Options

    * `:length` - sets the maximum number of bytes to read from the body for
      each chunk, defaults to `64_000` bytes
    * `:read_length` - sets the amount of bytes to read at one time from the
      underlying socket to fill the chunk, defaults to `64_000` bytes
    * `:read_timeout` - sets the timeout for each socket read, defaults to
      `5_000` milliseconds

  """
  @spec read_part_headers(t, Keyword.t()) :: {:ok, headers, t} | {:done, t}
  def read_part_headers(%Conn{adapter: {adapter, state}} = conn, opts \\ []) do
    opts = opts ++ [length: 64_000, read_length: 64_000, read_timeout: 5000]

    case init_multipart(conn) do
      {boundary, buffer} ->
        {data, state} = read_multipart_from_buffer_or_adapter(buffer, adapter, state, opts)
        read_part_headers(conn, data, boundary, adapter, state, opts)

      :done ->
        {:done, conn}
    end
  end

  defp read_part_headers(conn, data, boundary, adapter, state, opts) do
    case :plug_multipart.parse_headers(data, boundary) do
      {:ok, headers, rest} ->
        {:ok, headers, store_multipart(conn, {boundary, rest}, adapter, state)}

      :more ->
        {_, next, state} = next_multipart(adapter, state, opts)
        read_part_headers(conn, data <> next, boundary, adapter, state, opts)

      {:more, rest} ->
        {_, next, state} = next_multipart(adapter, state, opts)
        read_part_headers(conn, rest <> next, boundary, adapter, state, opts)

      {:done, _} ->
        {:done, store_multipart(conn, :done, adapter, state)}
    end
  end

  @doc """
  Reads the body of a multipart request.

  Returns `{:ok, body, conn}` if all body has been read,
  `{:more, binary, conn}` otherwise, and `{:done, conn}`
  if there is no more body.

  It accepts the same options as `read_body/2`.
  """
  @spec read_part_body(t, Keyword.t()) :: {:ok, binary, t} | {:more, binary, t} | {:done, t}
  def read_part_body(%Conn{adapter: {adapter, state}} = conn, opts) do
    case init_multipart(conn) do
      {boundary, buffer} ->
        # Note we will read the whole length from the socket
        # and then break it apart as necessary.
        length = Keyword.get(opts, :length, 8_000_000)
        {data, state} = read_multipart_from_buffer_or_adapter(buffer, adapter, state, opts)
        read_part_body(conn, data, "", length, boundary, adapter, state, opts)

      :done ->
        {:done, conn}
    end
  end

  defp read_part_body(%Conn{} = conn, data, acc, length, boundary, adapter, state, _opts)
       when byte_size(acc) > length do
    {:more, acc, store_multipart(conn, {boundary, data}, adapter, state)}
  end

  defp read_part_body(%Conn{} = conn, data, acc, length, boundary, adapter, state, opts) do
    case :plug_multipart.parse_body(data, boundary) do
      {:ok, body} ->
        {_, next, state} = next_multipart(adapter, state, opts)
        acc = prepend_unless_empty(acc, body)
        read_part_body(conn, next, acc, length, boundary, adapter, state, opts)

      {:ok, body, rest} ->
        {_, next, state} = next_multipart(adapter, state, opts)
        next = prepend_unless_empty(rest, next)
        acc = prepend_unless_empty(acc, body)
        read_part_body(conn, next, acc, length, boundary, adapter, state, opts)

      :done ->
        {:ok, acc, store_multipart(conn, {boundary, ""}, adapter, state)}

      {:done, body} ->
        {:ok, acc <> body, store_multipart(conn, {boundary, ""}, adapter, state)}

      {:done, body, rest} ->
        {:ok, acc <> body, store_multipart(conn, {boundary, rest}, adapter, state)}
    end
  end

  @compile {:inline, prepend_unless_empty: 2}
  defp prepend_unless_empty("", body), do: body
  defp prepend_unless_empty(acc, body), do: acc <> body

  defp init_multipart(%{private: %{plug_multipart: plug_multipart}}) do
    plug_multipart
  end

  defp init_multipart(%{req_headers: req_headers}) do
    {_, content_type} = List.keyfind(req_headers, "content-type", 0)
    {:ok, "multipart", _, keys} = Plug.Conn.Utils.content_type(content_type)

    case keys do
      %{"boundary" => boundary} -> {boundary, ""}
      %{} -> :done
    end
  end

  defp next_multipart(adapter, state, opts) do
    case adapter.read_req_body(state, opts) do
      {:ok, "", _} -> raise "invalid multipart, body terminated too soon"
      valid -> valid
    end
  end

  defp store_multipart(conn, multipart, adapter, state) do
    %{put_in(conn.private[:plug_multipart], multipart) | adapter: {adapter, state}}
  end

  defp read_multipart_from_buffer_or_adapter("", adapter, state, opts) do
    {_, data, state} = adapter.read_req_body(state, opts)
    {data, state}
  end

  defp read_multipart_from_buffer_or_adapter(buffer, _adapter, state, _opts) do
    {buffer, state}
  end

  @doc """
  Sends an informational response to the client.

  An informational response, such as an early hint, must happen prior to a response
  being sent. If an informational request is attempted after a response is sent then
  a `Plug.Conn.AlreadySentError` will be raised. Only status codes from 100-199 are valid.

  To use inform for early hints send one or more informs with a status of 103.

  If the adapter does not support informational responses then this is a noop.

  Most HTTP/1.1 clients do not properly support informational responses but some
  proxies require it to support server push for HTTP/2. You can call
  `get_http_protocol/1` to retrieve the protocol and version.
  """
  @spec inform(t, status, Keyword.t()) :: t
  def inform(%Conn{adapter: {adapter, _}} = conn, status, headers \\ []) do
    status_code = Plug.Conn.Status.code(status)

    case adapter_inform(conn, status_code, headers) do
      :ok ->
        conn

      {:ok, payload} ->
        put_in(conn.adapter, {adapter, payload})

      {:error, :not_supported} ->
        conn
    end
  end

  @doc """
  Sends an information response to a client but raises if the adapter does not support inform.

  See `inform/3` for more information.
  """
  @spec inform!(t, status, Keyword.t()) :: t
  def inform!(%Conn{adapter: {adapter, _}} = conn, status, headers \\ []) do
    status_code = Plug.Conn.Status.code(status)

    case adapter_inform(conn, status_code, headers) do
      :ok ->
        conn

      {:ok, payload} ->
        put_in(conn.adapter, {adapter, payload})

      {:error, :not_supported} ->
        raise "inform is not supported by #{inspect(adapter)}." <>
                "You should either delete the call to `inform!/3` or switch to an " <>
                "adapter that does support informational such as Plug.Cowboy"
    end
  end

  defp adapter_inform(_conn, status, _headers)
       when not (status >= 100 and status <= 199 and is_integer(status)) do
    raise ArgumentError, "inform expects a status code between 100 and 199, got: #{status}"
  end

  defp adapter_inform(%Conn{state: state}, _status, _headers)
       when state not in @unsent do
    raise AlreadySentError
  end

  defp adapter_inform(%Conn{adapter: {adapter, payload}}, status, headers) do
    adapter.inform(payload, status, headers)
  end

  @doc """
  Request a protocol upgrade from the underlying adapter.

  The precise semantics of an upgrade are deliberately left unspecified here in order to
  support arbitrary upgrades, even to protocols which may not exist today. The primary intent of
  this function is solely to allow an application to issue an upgrade request, not to manage how
  a given protocol upgrade takes place or what APIs the application must support in order to serve
  this updated protocol. For details in this regard, consult the documentation of the underlying
  adapter (such a [Plug.Cowboy](https://hexdocs.pm/plug_cowboy) or [Bandit](https://hexdocs.pm/bandit)).

  Takes an argument describing the requested upgrade (for example, `:websocket`), and an argument
  which contains arbitrary data which the underlying adapter is expected to interpret in the
  context of the requested upgrade.

  If the upgrade is accepted by the adapter, the returned `Plug.Conn` will have a `state` of
  `:upgraded`. This state is considered equivalently to a 'sent' state, and is subject to the same
  limitation on subsequent mutating operations. Note that there is no guarantee or expectation
  that the actual upgrade process has succeeded, or event that it is undertaken within this
  function; it is entirely possible (likely, even) that the server will only do the actual upgrade
  later in the connection lifecycle.

  If the adapter does not support the requested protocol this function will raise an
  `ArgumentError`. The underlying adapter may also signal errors in the provided arguments by
  raising; consult the corresponding adapter documentation for details.
  """
  @spec upgrade_adapter(t, atom, term) :: t
  def upgrade_adapter(%Conn{adapter: {adapter, payload}, state: state} = conn, protocol, args)
      when state in @unsent do
    case adapter.upgrade(payload, protocol, args) do
      {:ok, payload} ->
        %{conn | adapter: {adapter, payload}, state: :upgraded}

      {:error, :not_supported} ->
        raise ArgumentError, "upgrade to #{protocol} not supported by #{inspect(adapter)}"
    end
  end

  def upgrade_adapter(_conn, _protocol, _args) do
    raise AlreadySentError
  end

  @doc """
  Pushes a resource to the client.

  Server pushes must happen prior to a response being sent. If a server
  push is attempted after a response is sent then a `Plug.Conn.AlreadySentError`
  will be raised.

  If the adapter does not support server push then this is a noop.

  Note that certain browsers (such as Google Chrome) will not accept a pushed
  resource if your certificate is not trusted. In the case of Chrome this means
  a valid cert with a SAN. See https://www.chromestatus.com/feature/4981025180483584
  """
  @deprecated "Most browsers and clients have removed push support"
  @spec push(t, String.t(), Keyword.t()) :: t
  def push(%Conn{} = conn, path, headers \\ []) do
    adapter_push(conn, path, headers)
    conn
  end

  @doc """
  Pushes a resource to the client but raises if the adapter
  does not support server push.
  """
  @deprecated "Most browsers and clients have removed push support"
  @spec push!(t, String.t(), Keyword.t()) :: t
  def push!(%Conn{adapter: {adapter, _}} = conn, path, headers \\ []) do
    case adapter_push(conn, path, headers) do
      :ok ->
        conn

      _ ->
        raise "server push not supported by #{inspect(adapter)}." <>
                "You should either delete the call to `push!/3` or switch to an " <>
                "adapter that does support server push such as Plug.Cowboy."
    end
  end

  defp adapter_push(%Conn{state: state}, _path, _headers)
       when state not in @unsent do
    raise AlreadySentError
  end

  defp adapter_push(%Conn{adapter: {adapter, payload}}, path, headers) do
    headers =
      case List.keyfind(headers, "accept", 0) do
        nil -> [{"accept", MIME.from_path(path)} | headers]
        _ -> headers
      end

    adapter.push(payload, path, headers)
  end

  @doc """
  Fetches cookies from the request headers.

  ## Options

    * `:signed` - a list of one or more cookies that are signed and must
      be verified accordingly

    * `:encrypted` - a list of one or more cookies that are encrypted and
      must be decrypted accordingly

  See `put_resp_cookie/4` for more information.
  """
  @spec fetch_cookies(t, Keyword.t()) :: t
  def fetch_cookies(conn, opts \\ [])

  def fetch_cookies(%Conn{req_cookies: %Unfetched{}} = conn, opts) do
    %{resp_cookies: resp_cookies, req_headers: req_headers} = conn

    req_cookies =
      for {"cookie", cookie} <- req_headers,
          kv <- Plug.Conn.Cookies.decode(cookie),
          into: %{},
          do: kv

    cookies =
      Enum.reduce(resp_cookies, req_cookies, fn {key, opts}, acc ->
        if value = Map.get(opts, :value) do
          Map.put(acc, key, value)
        else
          Map.delete(acc, key)
        end
      end)

    fetch_cookies(%{conn | req_cookies: req_cookies, cookies: cookies}, opts)
  end

  def fetch_cookies(%Conn{} = conn, []) do
    conn
  end

  def fetch_cookies(%Conn{} = conn, opts) do
    %{req_cookies: req_cookies, cookies: cookies, secret_key_base: secret_key_base} = conn

    cookies =
      verify_or_decrypt(
        opts[:signed],
        req_cookies,
        cookies,
        &Plug.Crypto.verify(secret_key_base, &1 <> "_cookie", &2, keys: Plug.Keys)
      )

    cookies =
      verify_or_decrypt(
        opts[:encrypted],
        req_cookies,
        cookies,
        &Plug.Crypto.decrypt(secret_key_base, &1 <> "_cookie", &2, keys: Plug.Keys)
      )

    %{conn | cookies: cookies}
  end

  defp verify_or_decrypt(names, req_cookies, cookies, fun) do
    names
    |> List.wrap()
    |> Enum.reduce(cookies, fn name, acc ->
      if value = req_cookies[name] do
        case fun.(name, value) do
          {:ok, verified_value} -> Map.put(acc, name, verified_value)
          {_, _} -> Map.delete(acc, name)
        end
      else
        acc
      end
    end)
  end

  @doc """
  Puts a response cookie in the connection.

  If the `:sign` or `:encrypt` flag are given, then the cookie
  value can be any term.

  If the cookie is not signed nor encrypted, then the value must be a binary.
  Note the value is not automatically escaped. Therefore if you want to store
  values with non-alphanumeric characters, you must either sign or encrypt
  the cookie or consider explicitly escaping the cookie value by using a
  function such as `Base.encode64(value, padding: false)` when writing and
  `Base.decode64(encoded, padding: false)` when reading the cookie.
  It is important for padding to be disabled since `=` is not a valid
  character in cookie values.

  ## Signing and encrypting cookies

  This function allows you to automatically sign and encrypt cookies.
  When signing or encryption is enabled, then any Elixir value can be
  stored in the cookie (except anonymous functions for security reasons).
  Once a value is signed or encrypted, you must also call `fetch_cookies/2`
  with the name of the cookies that are either signed or encrypted.

  To sign, you would do:

      put_resp_cookie(conn, "my-cookie", %{user_id: user.id}, sign: true)

  and then:

      fetch_cookies(conn, signed: ~w(my-cookie))

  To encrypt, you would do:

      put_resp_cookie(conn, "my-cookie", %{user_id: user.id}, encrypt: true)

  and then:

      fetch_cookies(conn, encrypted: ~w(my-cookie))

  By default a signed or encrypted cookie is only valid for a day, unless
  a `:max_age` is specified.

  The signing and encryption keys are derived from the connection's
  `secret_key_base` using a salt that is built by appending "_cookie" to
  the cookie name. Care should be taken not to derive other keys using
  this value as the salt. Similarly do not use the same cookie name to
  store different values with distinct purposes.

  ## Options

    * `:domain` - the domain the cookie applies to
    * `:max_age` - the cookie max-age, in seconds. Providing a value for this
      option will set both the _max-age_ and _expires_ cookie attributes. Unset
      by default, which means the browser will default to a [session cookie](https://developer.mozilla.org/en-US/docs/Web/HTTP/Cookies#define_the_lifetime_of_a_cookie).
    * `:path` - the path the cookie applies to
    * `:http_only` - when `false`, the cookie is accessible beyond HTTP
    * `:secure` - if the cookie must be sent only over https. Defaults
      to true when the connection is HTTPS
    * `:extra` - string to append to cookie. Use this to take advantage of
      non-standard cookie attributes.
    * `:sign` - when true, signs the cookie
    * `:encrypt` - when true, encrypts the cookie
    * `:same_site` - set the cookie SameSite attribute to a string value.
      If no string value is set, the attribute is omitted.

  """
  @spec put_resp_cookie(t, binary, any(), Keyword.t()) :: t
  def put_resp_cookie(%Conn{} = conn, key, value, opts \\ [])
      when is_binary(key) and is_list(opts) do
    %{resp_cookies: resp_cookies, scheme: scheme} = conn
    {to_send_value, opts} = maybe_sign_or_encrypt_cookie(conn, key, value, opts)
    cookie = [{:value, to_send_value} | opts] |> Map.new() |> maybe_secure_cookie(scheme)
    resp_cookies = Map.put(resp_cookies, key, cookie)
    update_cookies(%{conn | resp_cookies: resp_cookies}, &Map.put(&1, key, value))
  end

  defp maybe_sign_or_encrypt_cookie(conn, key, value, opts) do
    {sign?, opts} = Keyword.pop(opts, :sign, false)
    {encrypt?, opts} = Keyword.pop(opts, :encrypt, false)

    case {sign?, encrypt?} do
      {true, true} ->
        raise ArgumentError,
              ":encrypt automatically implies :sign. Please pass only one or the other"

      {true, false} ->
        {Plug.Crypto.sign(conn.secret_key_base, key <> "_cookie", value, max_age(opts)), opts}

      {false, true} ->
        {Plug.Crypto.encrypt(conn.secret_key_base, key <> "_cookie", value, max_age(opts)), opts}

      {false, false} when is_binary(value) ->
        {value, opts}

      {false, false} ->
        raise ArgumentError, "cookie value must be a binary unless the cookie is signed/encrypted"
    end
  end

  defp max_age(opts) do
    [keys: Plug.Keys, max_age: Keyword.get(opts, :max_age, 86400)]
  end

  defp maybe_secure_cookie(cookie, :https), do: Map.put_new(cookie, :secure, true)
  defp maybe_secure_cookie(cookie, _), do: cookie

  @doc """
  Deletes a response cookie.

  Deleting a cookie requires the same options as to when the cookie was put.
  Check `put_resp_cookie/4` for more information.
  """
  @spec delete_resp_cookie(t, binary, Keyword.t()) :: t
  def delete_resp_cookie(%Conn{} = conn, key, opts \\ [])
      when is_binary(key) and is_list(opts) do
    %{resp_cookies: resp_cookies, scheme: scheme} = conn
    opts = opts ++ [universal_time: @epoch, max_age: 0]
    cookie = opts |> Map.new() |> maybe_secure_cookie(scheme)
    resp_cookies = Map.put(resp_cookies, key, cookie)
    update_cookies(%{conn | resp_cookies: resp_cookies}, &Map.delete(&1, key))
  end

  @doc """
  Fetches the session from the session store. Will also fetch cookies.
  """
  @spec fetch_session(t, Keyword.t()) :: t
  def fetch_session(conn, opts \\ [])

  def fetch_session(%Conn{private: private} = conn, _opts) do
    case Map.fetch(private, :plug_session_fetch) do
      {:ok, :done} -> conn
      {:ok, fun} -> conn |> fetch_cookies |> fun.()
      :error -> raise ArgumentError, "cannot fetch session without a configured session plug"
    end
  end

  @doc """
  Puts the specified `value` in the session for the given `key`.

  The key can be a string or an atom, where atoms are
  automatically converted to strings. Can only be invoked
  on unsent `conn`s. Will raise otherwise.
  """
  @spec put_session(t, String.t() | atom, any) :: t
  def put_session(%Conn{state: state}, _key, _value) when state not in @unsent,
    do: raise(AlreadySentError)

  def put_session(conn, key, value) when is_atom(key) or is_binary(key) do
    put_session(conn, &Map.put(&1, session_key(key), value))
  end

  @doc """
  Returns session value for the given `key`.

  Returns the `default` value if `key` does not exist.
  If `default` is not provided, `nil` is used.

  The key can be a string or an atom, where atoms are
  automatically converted to strings.
  """
  @spec get_session(t, String.t() | atom, any) :: any
  def get_session(conn, key, default \\ nil) when is_atom(key) or is_binary(key) do
    conn |> get_session |> Map.get(session_key(key), default)
  end

  @doc """
  Returns the whole session.

  Although `get_session/2` and `put_session/3` allow atom keys,
  they are always normalized to strings. So this function always
  returns a map with string keys.

  Raises if the session was not yet fetched.
  """
  @spec get_session(t) :: %{optional(String.t()) => any}
  def get_session(%Conn{private: private}) do
    if session = Map.get(private, :plug_session) do
      session
    else
      raise ArgumentError, "session not fetched, call fetch_session/2"
    end
  end

  @doc """
  Deletes `key` from session.

  The key can be a string or an atom, where atoms are
  automatically converted to strings.
  """
  @spec delete_session(t, String.t() | atom) :: t
  def delete_session(%Conn{state: state}, _key) when state not in @unsent,
    do: raise(AlreadySentError)

  def delete_session(conn, key) when is_atom(key) or is_binary(key) do
    put_session(conn, &Map.delete(&1, session_key(key)))
  end

  @doc """
  Clears the entire session.

  This function removes every key from the session, clearing the session.

  Note that, even if `clear_session/1` is used, the session is still sent to the
  client. If the session should be effectively *dropped*, `configure_session/2`
  should be used with the `:drop` option set to `true`.
  """
  @spec clear_session(t) :: t
  def clear_session(conn) do
    put_session(conn, fn _existing -> Map.new() end)
  end

  @doc """
  Configures the session.

  ## Options

    * `:renew` - When `true`, generates a new session id for the cookie
    * `:drop` - When `true`, drops the session, a session cookie will not be included in the
      response
    * `:ignore` - When `true`, ignores all changes made to the session in this request cycle

  ## Examples

      configure_session(conn, renew: true)

  """
  @spec configure_session(t, Keyword.t()) :: t
  def configure_session(conn, opts)

  def configure_session(%Conn{state: state}, _opts) when state not in @unsent,
    do: raise(AlreadySentError)

  def configure_session(conn, opts) do
    # Ensure the session is available.
    _ = get_session(conn)

    cond do
      opts[:renew] -> put_private(conn, :plug_session_info, :renew)
      opts[:drop] -> put_private(conn, :plug_session_info, :drop)
      opts[:ignore] -> put_private(conn, :plug_session_info, :ignore)
      true -> conn
    end
  end

  @doc ~S"""
  Registers a callback to be invoked before the response is sent.

  Callbacks are invoked in the reverse order they are defined (callbacks
  defined first are invoked last).

  ## Examples

  To log the status of response being sent:

      require Logger

      Plug.Conn.register_before_send(conn, fn conn ->
        Logger.info("Sent a #{conn.status} response")
        conn
      end)

  """
  @spec register_before_send(t, (t -> t)) :: t
  def register_before_send(conn, callback)

  def register_before_send(%Conn{state: state}, _callback)
      when state not in @unsent do
    raise AlreadySentError
  end

  def register_before_send(%Conn{} = conn, callback)
      when is_function(callback, 1) do
    update_in(conn.private[:before_send], &[callback | &1 || []])
  end

  @doc """
  Halts the `Plug` pipeline by preventing further plugs downstream from being
  invoked. See the docs for `Plug.Builder` for more information on halting a
  `Plug` pipeline.
  """
  @spec halt(t) :: t
  def halt(%Conn{} = conn) do
    %{conn | halted: true}
  end

  @doc """
  Returns the full request URL.
  """
  def request_url(%Conn{} = conn) do
    IO.iodata_to_binary([
      to_string(conn.scheme),
      "://",
      conn.host,
      request_url_port(conn.scheme, conn.port),
      conn.request_path,
      request_url_qs(conn.query_string)
    ])
  end

  ## Helpers

  defp run_before_send(%Conn{private: private} = conn, new) do
    conn = Enum.reduce(private[:before_send] || [], %{conn | state: new}, & &1.(&2))

    if conn.state != new do
      raise ArgumentError, "cannot send/change response from run_before_send callback"
    end

    %{conn | resp_headers: merge_headers(conn.resp_headers, conn.resp_cookies)}
  end

  defp merge_headers(headers, cookies) do
    Enum.reduce(cookies, headers, fn {key, opts}, acc ->
      value =
        key
        |> Plug.Conn.Cookies.encode(opts)
        |> verify_cookie!(key)

      [{"set-cookie", value} | acc]
    end)
  end

  defp verify_cookie!(cookie, key) when byte_size(cookie) > 4096 do
    raise Plug.Conn.CookieOverflowError,
          "cookie named #{inspect(key)} exceeds maximum size of 4096 bytes"
  end

  defp verify_cookie!(cookie, _key) do
    validate_header_key_value!("set-cookie", cookie)
  end

  defp update_cookies(%Conn{state: state}, _fun) when state not in @unsent do
    raise AlreadySentError
  end

  defp update_cookies(%Conn{cookies: %Unfetched{}} = conn, _fun), do: conn
  defp update_cookies(%Conn{cookies: cookies} = conn, fun), do: %{conn | cookies: fun.(cookies)}

  defp session_key(binary) when is_binary(binary), do: binary
  defp session_key(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp put_session(conn, fun) do
    private =
      conn.private
      |> Map.put(:plug_session, fun.(get_session(conn)))
      |> Map.put_new(:plug_session_info, :write)

    %{conn | private: private}
  end

  # host is an HTTP header, but if you store it in the main list it will be
  # overridden by conn.host.
  defp validate_req_header!(_adapter, "host") do
    raise InvalidHeaderError,
          "set the host header with %Plug.Conn{conn | host: \"example.com\"}"
  end

  defp validate_req_header!(adapter, key),
    do: validate_header_key_normalized_if_test!(adapter, key)

  defp validate_header_key_normalized_if_test!({Plug.Adapters.Test.Conn, _}, key) do
    if Application.fetch_env!(:plug, :validate_header_keys_during_test) and
         not normalized_header_key?(key) do
      raise InvalidHeaderError, "header key is not lowercase: " <> inspect(key)
    end
  end

  defp validate_header_key_normalized_if_test!(_adapter, _key) do
    :ok
  end

  # Any string containing an UPPERCASE char is not normalized.
  defp normalized_header_key?(<<h, _::binary>>) when h in ?A..?Z, do: false
  defp normalized_header_key?(<<_, t::binary>>), do: normalized_header_key?(t)
  defp normalized_header_key?(<<>>), do: true
  defp normalized_header_key?(_), do: false

  defp validate_header_key_value!(key, value) do
    case :binary.match(key, [":", "\n", "\r", "\x00"]) do
      {_, _} ->
        raise InvalidHeaderError,
              "header #{inspect(key)} contains a control feed (\\r), colon (:), newline (\\n) or null (\\x00)"

      :nomatch ->
        key
    end

    case :binary.match(value, ["\n", "\r", "\x00"]) do
      {_, _} ->
        raise InvalidHeaderError,
              "value for header #{inspect(key)} contains control feed (\\r), newline (\\n) or null (\\x00)" <>
                ": #{inspect(value)}"

      :nomatch ->
        value
    end
  end

  defp request_url_port(:http, 80), do: ""
  defp request_url_port(:https, 443), do: ""
  defp request_url_port(_, port), do: [?:, Integer.to_string(port)]

  defp request_url_qs(""), do: ""
  defp request_url_qs(qs), do: [??, qs]
end

defimpl Inspect, for: Plug.Conn do
  def inspect(conn, opts) do
    conn
    |> no_secret_key_base()
    |> no_adapter_data(opts)
    |> Inspect.Any.inspect(opts)
  end

  defp no_secret_key_base(%{secret_key_base: nil} = conn), do: conn
  defp no_secret_key_base(conn), do: %{conn | secret_key_base: :...}

  defp no_adapter_data(conn, %{limit: :infinity}), do: conn
  defp no_adapter_data(%{adapter: {adapter, _}} = conn, _), do: %{conn | adapter: {adapter, :...}}
end
