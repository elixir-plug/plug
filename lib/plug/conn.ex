alias Plug.Conn.Unfetched

defmodule Plug.Conn do
  @moduledoc """
  The Plug connection.

  This module defines a `Plug.Conn` struct and the main functions
  for working with Plug connections.

  Note request headers are normalized to lowercase and response
  headers are expected to have lower-case keys.

  ## Request fields

  These fields contain request information:

    * `host` - the requested host as a binary, example: `"www.example.com"`
    * `method` - the request method as a binary, example: `"GET"`
    * `path_info` - the path split into segments, example: `["hello", "world"]`
    * `script_name` - the initial portion of the URL's path that corresponds to the application
      routing, as segments, example: ["sub","app"].
    * `request_path` - the requested path, example: `/trailing/and//double//slashes/`
    * `port` - the requested port as an integer, example: `80`
    * `peer` - the actual TCP peer that connected, example: `{{127, 0, 0, 1}, 12345}`. Often this
      is not the actual IP and port of the client, but rather of a load-balancer or request-router.
    * `remote_ip` - the IP of the client, example: `{151, 236, 219, 228}`. This field is meant to
      be overwritten by plugs that understand e.g. the `X-Forwarded-For` header or HAProxy's PROXY
      protocol. It defaults to peer's IP.
    * `req_headers` - the request headers as a list, example: `[{"content-type", "text/plain"}]`.
      Note all headers will be downcased.
    * `scheme` - the request scheme as an atom, example: `:http`
    * `query_string` - the request query string as a binary, example: `"foo=bar"`

  ## Fetchable fields

  The request information in these fields is not populated until it is fetched
  using the associated `fetch_` function. For example, the `cookies` field uses
  `fetch_cookies/2`.

  If you access these fields before fetching them, they will be returned as
  `Plug.Conn.Unfetched` structs.

    * `cookies`- the request cookies with the response cookies
    * `body_params` - the request body params, populated through a `Plug.Parsers` parser.
    * `query_params` - the request query params, populated through `fetch_query_params/2`
    * `path_params` - the request path params, populated by routers such as `Plug.Router`
    * `params` - the request params, the result of merging the `:body_params` and `:query_params`
       with `:path_params`
    * `req_cookies` - the request cookies (without the response ones)

  ## Response fields

  These fields contain response information:

    * `resp_body` - the response body, by default is an empty string. It is set
      to nil after the response is sent, except for test connections.
    * `resp_charset` - the response charset, defaults to "utf-8"
    * `resp_cookies` - the response cookies with their name and options
    * `resp_headers` - the response headers as a list of tuples, by default `cache-control`
      is set to `"max-age=0, private, must-revalidate"`. Note, response headers
      are expected to have lower-case keys.
    * `status` - the response status

  Furthermore, the `before_send` field stores callbacks that are invoked
  before the connection is sent. Callbacks are invoked in the reverse order
  they are registered (callbacks registered first are invoked last) in order
  to reproduce a pipeline ordering.

  ## Connection fields

    * `assigns` - shared user data as a map
    * `owner` - the Elixir process that owns the connection
    * `halted` - the boolean status on whether the pipeline was halted
    * `secret_key_base` - a secret key used to verify and encrypt cookies.
      the field must be set manually whenever one of those features are used.
      This data must be kept in the connection and never used directly, always
      use `Plug.Crypto.KeyGenerator.generate/3` to derive keys from it
    * `state` - the connection state

  The connection state is used to track the connection lifecycle. It starts as
  `:unset` but is changed to `:set` (via `resp/3`) or `:set_chunked`
  (used only for `before_send` callbacks by `send_chunked/2`) or `:file`
  (when invoked via `send_file/3`). Its final result is `:sent`, `:file` or
  `:chunked` depending on the response model.

  ## Private fields

  These fields are reserved for libraries/framework usage.

    * `adapter` - holds the adapter information in a tuple
    * `private` - shared library data as a map

  ## Protocols

  `Plug.Conn` implements both the Collectable and Inspect protocols
  out of the box. The inspect protocol provides a nice representation
  of the connection while the collectable protocol allows developers
  to easily chunk data. For example:

      # Send the chunked response headers
      conn = send_chunked(conn, 200)

      # Pipe the given list into a connection
      # Each item is emitted as a chunk
      Enum.into(~w(each chunk as a word), conn)

  ## Custom status codes

  Plug allows status codes to be overridden or added in order to allow new codes
  not directly specified by Plug or its adapters. Adding or overriding a status
  code is done through the Mix configuration of the `:plug` application. For
  example, to override the existing 404 reason phrase for the 404 status code
  ("Not Found" by default) and add a new 451 status code, the following config
  can be specified:

      config :plug, :statuses, %{
        404 => "Actually This Was Found",
        451 => "Unavailable For Legal Reasons"
      }

  As this configuration is Plug specific, Plug will need to be recompiled for
  the changes to take place: this will not happen automatically as dependencies
  are not automatically recompiled when their configuration changes. To recompile
  Plug:

      mix deps.clean --build plug

  The atoms that can be used in place of the status code in many functions are
  inflected from the reason phrase of the status code. With the above
  configuration, the following will all work:

      put_status(conn, :not_found)                     # 404
      put_status(conn, :actually_this_was_found)       # 404
      put_status(conn, :unavailable_for_legal_reasons) # 451

  Even though 404 has been overridden, the `:not_found` atom can still be used
  to set the status to 404 as well as the new atom `:actually_this_was_found`
  inflected from the reason phrase "Actually This Was Found".
  """

  @type adapter :: {module, term}
  @type assigns :: %{atom => any}
  @type before_send :: [(t -> t)]
  @type body :: iodata
  @type cookies :: %{binary => binary}
  @type halted :: boolean
  @type headers :: [{binary, binary}]
  @type host :: binary
  @type int_status :: non_neg_integer | nil
  @type owner :: pid
  @type method :: binary
  @type param :: binary | %{binary => param} | [param]
  @type params :: %{binary => param}
  @type peer :: {:inet.ip_address(), :inet.port_number()}
  @type port_number :: :inet.port_number()
  @type query_string :: String.t()
  @type resp_cookies :: %{binary => %{}}
  @type scheme :: :http | :https
  @type secret_key_base :: binary | nil
  @type segments :: [binary]
  @type state :: :unset | :set | :set_chunked | :set_file | :file | :chunked | :sent
  @type status :: atom | int_status

  @type t :: %__MODULE__{
          adapter: adapter,
          assigns: assigns,
          before_send: before_send,
          body_params: params | Unfetched.t(),
          cookies: cookies | Unfetched.t(),
          host: host,
          method: method,
          owner: owner,
          params: params | Unfetched.t(),
          path_info: segments,
          path_params: params,
          port: :inet.port_number(),
          private: assigns,
          query_params: params | Unfetched.t(),
          query_string: query_string,
          peer: peer,
          remote_ip: :inet.ip_address(),
          req_cookies: cookies | Unfetched.t(),
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
            before_send: [],
            body_params: %Unfetched{aspect: :body_params},
            cookies: %Unfetched{aspect: :cookies},
            halted: false,
            host: "www.example.com",
            method: "GET",
            owner: nil,
            params: %Unfetched{aspect: :params},
            path_params: %{},
            path_info: [],
            port: 0,
            private: %{},
            query_params: %Unfetched{aspect: :query_params},
            query_string: "",
            peer: nil,
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
  @already_sent {:plug_conn, :sent}
  @unsent [:unset, :set, :set_chunked, :set_file]

  @doc """
  Assigns a value to a key in the connection.

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
  @spec merge_assigns(t, Keyword.t()) :: t
  def merge_assigns(%Conn{assigns: assigns} = conn, keyword) when is_list(keyword) do
    %{conn | assigns: Enum.into(keyword, assigns)}
  end

  @doc false
  @spec async_assign(t, atom, (() -> term)) :: t
  def async_assign(%Conn{} = conn, key, fun) when is_atom(key) and is_function(fun, 0) do
    IO.warn("Plug.Conn.async_assign/3 is deprecated, please call assign + Task.async instead")
    assign(conn, key, Task.async(fun))
  end

  @doc false
  @spec await_assign(t, atom, timeout) :: t
  def await_assign(%Conn{} = conn, key, timeout \\ 5000) when is_atom(key) do
    IO.warn(
      "Plug.Conn.await_assign/3 is deprecated, please fetch the assign and call Task.await instead"
    )

    task = Map.fetch!(conn.assigns, key)
    assign(conn, key, Task.await(task, timeout))
  end

  @doc """
  Assigns a new **private** key and value in the connection.

  This storage is meant to be used by libraries and frameworks to avoid writing
  to the user storage (the `:assigns` field). It is recommended for
  libraries/frameworks to prefix the keys with the library name.

  For example, if some plug needs to store a `:hello` key, it
  should do so as `:plug_hello`:

      iex> conn.private[:plug_hello]
      nil
      iex> conn = put_private(conn, :plug_hello, :world)
      iex> conn.private[:plug_hello]
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

      iex> conn.private[:plug_hello]
      nil
      iex> conn = merge_private(conn, plug_hello: :world)
      iex> conn.private[:plug_hello]
      :world
  """
  @spec merge_private(t, Keyword.t()) :: t
  def merge_private(%Conn{private: private} = conn, keyword) when is_list(keyword) do
    %{conn | private: Enum.into(keyword, private)}
  end

  @doc """
  Stores the given status code in the connection.

  The status code can be `nil`, an integer or an atom. The list of allowed
  atoms is available in `Plug.Conn.Status`.

  Raises a `Plug.Conn.AlreadySentError` if the connection has already been
  `:sent` or `:chunked`.
  """
  @spec put_status(t, status) :: t
  def put_status(%Conn{state: :sent}, _status), do: raise(AlreadySentError)
  def put_status(%Conn{} = conn, nil), do: %{conn | status: nil}
  def put_status(%Conn{} = conn, status), do: %{conn | status: Plug.Conn.Status.code(status)}

  @doc """
  Sends a response to the client.

  It expects the connection state to be `:set`, otherwise raises an
  `ArgumentError` for `:unset` connections or a `Plug.Conn.AlreadySentError` for
  already `:sent` connections.

  At the end sets the connection state to `:sent`.
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

  It expects a connection that has not been `:sent` yet and sets its
  state to `:file` afterwards. Otherwise raises `Plug.Conn.AlreadySentError`.

  ## Examples

      Plug.Conn.send_file(conn, 200, "README.md")

  """
  @spec send_file(t, status, filename :: binary, offset :: integer, length :: integer | :all) ::
          t | no_return
  def send_file(conn, status, file, offset \\ 0, length \\ :all)

  def send_file(%Conn{state: state}, status, _file, _offset, _length)
      when not (state in @unsent) do
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

  It expects a connection that has not been `:sent` yet and sets its
  state to `:chunked` afterwards. Otherwise raises `Plug.Conn.AlreadySentError`.
  """
  @spec send_chunked(t, status) :: t | no_return
  def send_chunked(%Conn{state: state}, status)
      when not (state in @unsent) do
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

      ~w(each chunk as a word)
      |> Enum.reduce_while(conn, fn (chunk, conn) ->
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

  See `send_resp/1` for more information.
  """
  @spec send_resp(t, status, body) :: t | no_return
  def send_resp(%Conn{} = conn, status, body) do
    conn |> resp(status, body) |> send_resp()
  end

  @doc """
  Sets the response to the given `status` and `body`.

  It sets the connection state to `:set` (if not already `:set`)
  and raises `Plug.Conn.AlreadySentError` if it was already `:sent`.
  """
  @spec resp(t, status, body) :: t
  def resp(%Conn{state: state}, status, _body)
      when not (state in @unsent) do
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
  Returns the values of the request header specified by `key`.
  """
  @spec get_req_header(t, binary) :: [binary]
  def get_req_header(%Conn{req_headers: headers}, key) when is_binary(key) do
    for {k, v} <- headers, k == key, do: v
  end

  @doc """
  Adds a new request header (`key`) if not present, otherwise replaces the
  previous value of that header with `value`.

  It is recommended for header keys to be in lower-case, to avoid sending
  duplicate keys in a request. As a convenience, this is validated during
  testing which raises a `Plug.Conn.InvalidHeaderError` if the header key
  is not lowercase.

  Raises a `Plug.Conn.AlreadySentError` if the connection has already been
  `:sent` or `:chunked`.
  """
  @spec put_req_header(t, binary, binary) :: t
  def put_req_header(%Conn{state: :sent}, _key, _value) do
    raise AlreadySentError
  end

  def put_req_header(%Conn{adapter: adapter, req_headers: headers} = conn, key, value)
      when is_binary(key) and is_binary(value) do
    validate_header_key_if_test!(adapter, key)
    %{conn | req_headers: List.keystore(headers, key, 0, {key, value})}
  end

  @doc """
  Deletes a request header if present.

  Raises a `Plug.Conn.AlreadySentError` if the connection has already been
  `:sent` or `:chunked`.
  """
  @spec delete_req_header(t, binary) :: t
  def delete_req_header(%Conn{state: :sent}, _key) do
    raise AlreadySentError
  end

  def delete_req_header(%Conn{state: :chunked}, _key) do
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
  `:sent` or `:chunked`.
  """
  @spec update_req_header(t, binary, binary, (binary -> binary)) :: t
  def update_req_header(%Conn{state: :sent}, _key, _initial, _fun) do
    raise AlreadySentError
  end

  def update_req_header(%Conn{state: :chunked}, _key, _initial, _fun) do
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
    for {k, v} <- headers, k == key, do: v
  end

  @doc ~S"""
  Adds a new response header (`key`) if not present, otherwise replaces the
  previous value of that header with `value`.

  It is recommended for header keys to be in lower-case, to avoid sending
  duplicate keys in a request. As a convenience, this is validated during
  testing which raises a `Plug.Conn.InvalidHeaderError` if the header key
  is not lowercase.

  Raises a `Plug.Conn.AlreadySentError` if the connection has already been
  `:sent` or `:chunked`.

  Raises a `Plug.Conn.InvalidHeaderError` if the header value contains control
  feed (`\r`) or newline (`\n`) characters.
  """
  @spec put_resp_header(t, binary, binary) :: t
  def put_resp_header(%Conn{state: :sent}, _key, _value) do
    raise AlreadySentError
  end

  def put_resp_header(%Conn{state: :chunked}, _key, _value) do
    raise AlreadySentError
  end

  def put_resp_header(%Conn{adapter: adapter, resp_headers: headers} = conn, key, value)
      when is_binary(key) and is_binary(value) do
    validate_header_key_if_test!(adapter, key)
    validate_header_value!(key, value)
    %{conn | resp_headers: List.keystore(headers, key, 0, {key, value})}
  end

  @doc ~S"""
  Prepends the list of headers to the connection response headers.

  Similar to `put_resp_header` this functions adds a new response header
  (`key`) but rather then replacing the existing one it prepends another header
  with the same `key`.

  It is recommended for header keys to be in lower-case, to avoid sending
  duplicate keys in a request. As a convenience, this is validated during
  testing which raises a `Plug.Conn.InvalidHeaderError` if the header key
  is not lowercase.

  Raises a `Plug.Conn.AlreadySentError` if the connection has already been
  `:sent` or `:chunked`.

  Raises a `Plug.Conn.InvalidHeaderError` if the header value contains control
  feed (`\r`) or newline (`\n`) characters.
  """
  @spec prepend_resp_headers(t, headers) :: t
  def prepend_resp_headers(%Conn{state: :sent}, _headers) do
    raise AlreadySentError
  end

  def prepend_resp_headers(%Conn{state: :chunked}, _headers) do
    raise AlreadySentError
  end

  def prepend_resp_headers(%Conn{adapter: adapter, resp_headers: resp_headers} = conn, headers)
      when is_list(headers) do
    for {key, value} <- headers do
      validate_header_key_if_test!(adapter, key)
      validate_header_value!(key, value)
    end

    %{conn | resp_headers: headers ++ resp_headers}
  end

  @doc """
  Merges a series of response headers into the connection.

  ## Example

      iex> conn = merge_resp_headers(conn, [{"content-type", "text/plain"}, {"X-1337", "5P34K"}])
  """
  @spec merge_resp_headers(t, Enum.t()) :: t
  def merge_resp_headers(%Conn{state: :sent}, _headers) do
    raise AlreadySentError
  end

  def merge_resp_headers(%Conn{state: :chunked}, _headers) do
    raise AlreadySentError
  end

  def merge_resp_headers(conn, headers) when headers == %{} do
    conn
  end

  def merge_resp_headers(%Conn{resp_headers: current, adapter: adapter} = conn, headers) do
    headers =
      Enum.reduce(headers, current, fn {key, value}, acc
                                       when is_binary(key) and is_binary(value) ->
        validate_header_key_if_test!(adapter, key)
        validate_header_value!(key, value)
        List.keystore(acc, key, 0, {key, value})
      end)

    %{conn | resp_headers: headers}
  end

  @doc """
  Deletes a response header if present.

  Raises a `Plug.Conn.AlreadySentError` if the connection has already been
  `:sent` or `:chunked`.
  """
  @spec delete_resp_header(t, binary) :: t
  def delete_resp_header(%Conn{state: :sent}, _key) do
    raise AlreadySentError
  end

  def delete_resp_header(%Conn{state: :chunked}, _key) do
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
  `:sent` or `:chunked`.
  """
  @spec update_resp_header(t, binary, binary, (binary -> binary)) :: t
  def update_resp_header(%Conn{state: :sent}, _key, _initial, _fun) do
    raise AlreadySentError
  end

  def update_resp_header(%Conn{state: :chunked}, _key, _initial, _fun) do
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

  Params are decoded as "x-www-form-urlencoded" in which key/value pairs
  are separated by `&` and keys are separated from values by `=`.

  This function does not fetch parameters from the body. To fetch
  parameters from the body, use the `Plug.Parsers` plug.

  ## Options

    * `:length` - the maximum query string length. Defaults to 1_000_000 bytes.

  """
  @spec fetch_query_params(t, Keyword.t()) :: t
  def fetch_query_params(conn, opts \\ [])

  def fetch_query_params(%Conn{query_params: %Unfetched{}} = conn, opts) do
    %{params: params, query_string: query_string} = conn
    Plug.Conn.Utils.validate_utf8!(query_string, InvalidQueryError, "query string")
    length = Keyword.get(opts, :length, 1_000_000)

    if byte_size(query_string) > length do
      raise InvalidQueryError,
            "maximum query string length is #{length}, got a query with #{byte_size(query_string)} bytes"
    end

    query_params = Plug.Conn.Query.decode(query_string)

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

  This function reads a chunk of the request body up to a given `:length`. If
  there is more data to be read, then `{:more, partial_body, conn}` is
  returned. Otherwise `{:ok, body, conn}` is returned. In case of an error
  reading the socket, `{:error, reason}` is returned as per `:gen_tcp.recv/2`.

  Like all functions in this module, the `conn` returned by `read_body` must
  be passed to the next stage of your pipeline and should not be ignored.

  In order to, for instance, support slower clients you can tune the
  `:read_length` and `:read_timeout` options. These specify how much time should
  be allowed to pass for each read from the underlying socket.

  Because the request body can be of any size, reading the body will only
  work once, as Plug will not cache the result of these operations. If you
  need to access the body multiple times, it is your responsibility to store
  it. Finally keep in mind some plugs like `Plug.Parsers` may read the body,
  so the body may be unavailable after being accessed by such plugs.

  This function is able to handle both chunked and identity transfer-encoding
  by default.

  ## Options

    * `:length` - sets the maximum number of bytes to read from the body on
      every call, defaults to 8_000_000 bytes
    * `:read_length` - sets the amount of bytes to read at one time from the
      underlying socket to fill the chunk, defaults to 1_000_000 bytes
    * `:read_timeout` - sets the timeout for each socket read, defaults to
      15_000ms

  The values above are not meant to be exact. For example, setting the
  length to 8_000_000 may end up reading some hundred bytes more from
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

  Once `read_part_headers/2` is invoked, a developer may call
  `read_part_body/2` to read the body associated to the headers.
  If `read_part_headers/2` is called instead, the body is automatically
  skipped until the next part headers.

  ## Options

    * `:length` - sets the maximum number of bytes to read from the body for
      each chunk, defaults to 64_000 bytes
    * `:read_length` - sets the amount of bytes to read at one time from the
      underlying socket to fill the chunk, defaults to 64_000 bytes
    * `:read_timeout` - sets the timeout for each socket read, defaults to
      5_000ms

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
  def read_part_body(%{adapter: {adapter, state}} = conn, opts) do
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

  defp read_part_body(conn, data, acc, length, boundary, adapter, state, _opts)
       when byte_size(acc) > length do
    {:more, acc, store_multipart(conn, {boundary, data}, adapter, state)}
  end

  defp read_part_body(conn, data, acc, length, boundary, adapter, state, opts) do
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
  Pushes a resource to the client.

  Server pushes must happen prior to a response being sent. If a server
  push is attempted after a response is sent then a `Plug.Conn.AlreadySentError`
  will be raised.

  If the adapter does not support server push then this is a noop.
  """
  @spec push(t, String.t(), Keyword.t()) :: t
  def push(%Conn{} = conn, path, headers \\ []) do
    adapter_push(conn, path, headers)
    conn
  end

  @doc """
  Pushes a resource to the client but raises if the adapter
  does not support server push.
  """
  @spec push!(t, String.t(), Keyword.t()) :: t
  def push!(%Conn{adapter: {adapter, _}} = conn, path, headers \\ []) do
    case adapter_push(conn, path, headers) do
      :ok ->
        conn

      _ ->
        raise "server push not supported by #{inspect(adapter)}." <>
                "You should either delete the call to `push!/3` or switch to an " <>
                "adapter that does support server push such as Plug.Adapters.Cowboy2."
    end
  end

  defp adapter_push(%Conn{state: state}, _path, _headers)
       when not (state in @unsent) do
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
  """
  @spec fetch_cookies(t, Keyword.t()) :: t
  def fetch_cookies(conn, opts \\ [])

  def fetch_cookies(%Conn{req_cookies: %Unfetched{}} = conn, _opts) do
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

    %{conn | req_cookies: req_cookies, cookies: cookies}
  end

  def fetch_cookies(%Conn{} = conn, _opts) do
    conn
  end

  @doc """
  Puts a response cookie.

  The cookie value is not automatically escaped. Therefore, if you
  want to store values with comma, quotes, etc, you need to explicitly
  escape them or use a function such as `Base.encode64(value, padding: false)`
  when writing and `Base.decode64(encoded, padding: false)` when reading
  the cookie. Padding needs to be disabled since `=` is not a valid character
  in cookie values.

  ## Options

    * `:domain` - the domain the cookie applies to
    * `:max_age` - the cookie max-age, in seconds. Providing a value for this
      option will set both the _max-age_ and _expires_ cookie attributes
    * `:path` - the path the cookie applies to
    * `:http_only` - when false, the cookie is accessible beyond http
    * `:secure` - if the cookie must be sent only over https. Defaults
      to true when the connection is https
    * `:extra` - string to append to cookie. Use this to take advantage of
      non-standard cookie attributes.

  """
  @spec put_resp_cookie(t, binary, binary, Keyword.t()) :: t
  def put_resp_cookie(%Conn{} = conn, key, value, opts \\ [])
      when is_binary(key) and is_binary(value) and is_list(opts) do
    %{resp_cookies: resp_cookies, scheme: scheme} = conn
    cookie = [{:value, value} | opts] |> :maps.from_list() |> maybe_secure_cookie(scheme)
    resp_cookies = Map.put(resp_cookies, key, cookie)
    update_cookies(%{conn | resp_cookies: resp_cookies}, &Map.put(&1, key, value))
  end

  defp maybe_secure_cookie(cookie, :https), do: Map.put_new(cookie, :secure, true)
  defp maybe_secure_cookie(cookie, _), do: cookie

  @epoch {{1970, 1, 1}, {0, 0, 0}}

  @doc """
  Deletes a response cookie.

  Deleting a cookie requires the same options as to when the cookie was put.
  Check `put_resp_cookie/4` for more information.
  """
  @spec delete_resp_cookie(t, binary, Keyword.t()) :: t
  def delete_resp_cookie(%Conn{resp_cookies: resp_cookies} = conn, key, opts \\ [])
      when is_binary(key) and is_list(opts) do
    opts = [universal_time: @epoch, max_age: 0] ++ opts
    resp_cookies = Map.put(resp_cookies, key, :maps.from_list(opts))
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
  def put_session(%Conn{state: state}, _key, _value) when not (state in @unsent),
    do: raise(AlreadySentError)

  def put_session(conn, key, value) do
    put_session(conn, &Map.put(&1, session_key(key), value))
  end

  @doc """
  Returns session value for the given `key`. If `key`
  is not set, `nil` is returned.

  The key can be a string or an atom, where atoms are
  automatically converted to strings.
  """
  @spec get_session(t, String.t() | atom) :: any
  def get_session(conn, key) do
    conn |> get_session |> Map.get(session_key(key))
  end

  @doc """
  Deletes the session for the given `key`.

  The key can be a string or an atom, where atoms are
  automatically converted to strings.
  """
  @spec delete_session(t, String.t() | atom) :: t
  def delete_session(%Conn{state: state}, _key) when not (state in @unsent),
    do: raise(AlreadySentError)

  def delete_session(conn, key) do
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

    * `:renew` - generates a new session id for the cookie
    * `:drop` - drops the session, a session cookie will not be included in the
      response
    * `:ignore` - ignores all changes made to the session in this request cycle

  """
  @spec configure_session(t, Keyword.t()) :: t
  def configure_session(%Conn{state: state}, _opts) when not (state in @unsent),
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

  @doc """
  Registers a callback to be invoked before the response is sent.

  Callbacks are invoked in the reverse order they are defined (callbacks
  defined first are invoked last).
  """
  @spec register_before_send(t, (t -> t)) :: t
  def register_before_send(%Conn{state: state}, _callback)
      when not (state in @unsent) do
    raise AlreadySentError
  end

  def register_before_send(%Conn{before_send: before_send} = conn, callback)
      when is_function(callback, 1) do
    %{conn | before_send: [callback | before_send]}
  end

  @doc """
  Halts the Plug pipeline by preventing further plugs downstream from being
  invoked. See the docs for `Plug.Builder` for more information on halting a
  plug pipeline.
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

  defp run_before_send(%Conn{before_send: before_send} = conn, new) do
    conn = Enum.reduce(before_send, %{conn | state: new}, & &1.(&2))

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
    validate_header_value!("set-cookie", cookie)
  end

  defp update_cookies(%Conn{state: :sent}, _fun), do: raise(AlreadySentError)
  defp update_cookies(%Conn{state: :chunked}, _fun), do: raise(AlreadySentError)
  defp update_cookies(%Conn{cookies: %Unfetched{}} = conn, _fun), do: conn
  defp update_cookies(%Conn{cookies: cookies} = conn, fun), do: %{conn | cookies: fun.(cookies)}

  defp session_key(binary) when is_binary(binary), do: binary
  defp session_key(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp get_session(%Conn{private: private}) do
    if session = Map.get(private, :plug_session) do
      session
    else
      raise ArgumentError, "session not fetched, call fetch_session/2"
    end
  end

  defp put_session(conn, fun) do
    private =
      conn.private
      |> Map.put(:plug_session, fun.(get_session(conn)))
      |> Map.put_new(:plug_session_info, :write)

    %{conn | private: private}
  end

  defp validate_header_key_if_test!({Plug.Adapters.Test.Conn, _}, key) do
    if Application.fetch_env!(:plug, :validate_header_keys_during_test) and
         not valid_header_key?(key) do
      raise InvalidHeaderError, "header key is not lowercase: " <> inspect(key)
    end
  end

  defp validate_header_key_if_test!(_adapter, _key) do
    :ok
  end

  # Any string containing an UPPERCASE char is not valid.
  defp valid_header_key?(<<h, _::binary>>) when h in ?A..?Z, do: false
  defp valid_header_key?(<<_, t::binary>>), do: valid_header_key?(t)
  defp valid_header_key?(<<>>), do: true
  defp valid_header_key?(_), do: false

  defp validate_header_value!(key, value) do
    case :binary.match(value, ["\n", "\r"]) do
      {_, _} ->
        raise InvalidHeaderError,
              "value for header #{inspect(key)} contains control feed (\\r) or newline " <>
                "(\\n): #{inspect(value)}"

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
    conn =
      if opts.limit == :infinity do
        conn
      else
        update_in(conn.adapter, fn {adapter, _data} -> {adapter, :...} end)
      end

    Inspect.Any.inspect(conn, opts)
  end
end

defimpl Collectable, for: Plug.Conn do
  def into(conn) do
    IO.warn(
      "using Enum.into/2 for conn is deprecated, use `Plug.Conn.chunk/2` " <>
        "and `Enum.reduce_while/3` instead (see the Plug.Conn.chunk/2 docs for an example)"
    )

    fun = fn
      conn, {:cont, x} ->
        {:ok, conn} = Plug.Conn.chunk(conn, x)
        conn

      conn, _ ->
        conn
    end

    {conn, fun}
  end
end
