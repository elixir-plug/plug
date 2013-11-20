alias Plug.Connection.Unfetched

defrecord Plug.Conn,
    adapter: nil,
    assigns: [],
    host: nil,
    method: nil,
    params: Unfetched[aspect: :params],
    path_info: [],
    port: nil,
    query_string: nil,
    req_headers: [],
    resp_body: "",
    resp_headers: [{"cache-control", "max-age=0, private, must-revalidate"}],
    scheme: nil,
    state: :unsent,
    status: nil do

  @type adapter  :: { module, term }
  @type assigns  :: Keyword.t
  @type body     :: binary
  @type headers  :: [{ binary, binary }]
  @type host     :: binary
  @type method   :: binary
  @type scheme   :: :http | :https
  @type segments :: [binary]
  @type state    :: :unsent | :sent
  @type status   :: non_neg_integer
  @type param    :: binary | [{ binary, param }] | [param]
  @type params   :: [{ binary, param }]

  record_type adapter: adapter,
              assigns: assigns,
              host: host,
              method: method,
              params: params | Unfetched.t,
              path_info: segments,
              port: 0..65535,
              req_headers: [],
              resp_body: body | nil,
              resp_headers: headers,
              scheme: scheme,
              state: state,
              status: status

  @moduledoc """
  The connection record.

  It is recommended to use the record for reading data,
  all connection manipulation should be done via the functions
  in `Plug.Connection` module.

  Both request and response headers are expected to have
  lower-cased keys.

  ## Request fields

  Those fields contain request information:

  * `host` - the requested host as a binary, example: `"www.example.com"`
  * `method` - the request method as a binary, example: `"GET"`
  * `path_info` - the path split into segments, example: `["hello", "world"]`
  * `port` - the requested port as an integer, example: `80`
  * `req_headers` - the request headers as a list, example: `[{ "content-type", "text/plain" }]`
  * `scheme` - the request scheme as an atom, example: `:http`
  * `query_string` - the request query string as a binary, example: `"foo=bar"`

  ## Fetchable request fields

  Those fields contain request information but they need to be explicitly fetched.
  Before fetching those fields return a `Plug.Connection.Unfetched` record.

  * `params` - the request params

  ## Response fields

  Those fields contain response information:

  * `resp_body` - the response body, by default is an empty string, set to nil after sening
  * `resp_content_type` - the response content-type, by default is nil
  * `resp_charset` - the response charset, defaults to "utf-8"
  * `resp_headers` - the response headers as a dict,
                     by default `cache-control` is set to `"max-age=0, private, must-revalidate"`
  * `status` - the response status

  ## Connection fields

  * `assigns` - shared user data as a dict
  * `state` - the connection state

  The connection state is used to track the connection lifecycle. It starts
  as `:unsent` but is changed to `:sent` as soon as the response is sent.

  ## Private fields

  Those fields are reserved for libraries/framework usage.

  * `adapter` - holds the adapter information in a tuple
  """
end

defmodule Plug.Connection do
  @moduledoc """
  Functions for manipulating the connection.
  """

  defexception NotSentError,
    message: "no response was set nor sent from the connection"

  defexception AlreadySentError,
    message: "the response was already sent"

  alias Plug.Conn
  @already_sent { :plug_conn, :sent }

  @doc """
  Assigns a new key and value in the connection.

  ## Examples

      iex> conn.assigns[:hello]
      nil
      iex> conn = assign(conn, :hello, :world)
      iex> conn.assigns[:hello]
      :world

  """
  @spec assign(Conn.t, atom, term) :: Conn.t
  def assign(Conn[assigns: assigns] = conn, key, value) when is_atom(key) do
    conn.assigns(Keyword.put(assigns, key, value))
  end

  @doc """
  Sends a response to the client. It is expected that the connection
  state is set to `:unsent`, otherwise `Plug.Connection.AlreadySentError`
  is raised.

  If is also expected for the status to be set to an integer.
  """
  @spec send(Conn.t) :: Conn.t | no_return
  def send(conn)

  def send(Conn[status: nil]) do
    raise ArgumentError, message: "cannot send a response when there is no status code"
  end

  def send(Conn[adapter: { adapter, payload }, state: :unsent] = conn) do
    self() <- @already_sent
    payload = adapter.send_resp(payload, conn.status, conn.resp_headers, conn.resp_body)
    conn.adapter({ adapter, payload }).state(:sent).resp_body(nil)
  end

  def send(Conn[]) do
    raise AlreadySentError
  end

  @doc """
  Sends a response to the client the given status and body.
  See `send/1` for more information.
  """
  @spec send(Conn.t, Conn.status, Conn.body) :: Conn.t | no_return
  def send(Conn[] = conn, status, body) when is_integer(status) and is_binary(body) do
    send(conn.status(status).resp_body(body))
  end

  @doc """
  Sets the response to given status and body.
  """
  @spec resp(Conn.t, Conn.status, Conn.body) :: Conn.t
  def resp(Conn[] = conn, status, resp_body) when is_integer(status) and is_binary(resp_body) do
    conn.status(status).resp_body(resp_body)
  end

  @doc """
  Puts a new response header.
  Previous entries of the same headers are removed.
  """
  @spec put_resp_header(Conn.t, binary, binary) :: Conn.t
  def put_resp_header(Conn[resp_headers: headers] = conn, key, value) do
    conn.resp_headers(:lists.keystore(key, 1, headers, { key, value }))
  end

  @doc """
  Deletes a response header.
  """
  @spec delete_resp_header(Conn.t, binary) :: Conn.t
  def delete_resp_header(Conn[resp_headers: headers] = conn, key) do
    conn.resp_headers(:lists.keydelete(key, 1, headers))
  end

  @doc """
  Puts the content-type response header taking into
  account the charset.
  """
  @spec put_resp_content_type(Conn.t, binary, binary | nil) :: Conn.t
  def put_resp_content_type(conn, content_type, charset // "utf-8") do
    value =
      if nil?(charset) do
        content_type
      else
        content_type <> "; charset=" <> charset
      end
    put_resp_header(conn, "content-type", value)
  end

  @doc """
  Fetches parameters from the query string. This function does not
  fetch parameters from the body. To fetch parameters from the body,
  use the `Plug.Parsers` plug.
  """
  @spec fetch_params(Conn.t) :: Conn.t
  def fetch_params(Conn[params: Plug.Connection.Unfetched[], query_string: query_string] = conn) do
    conn.params(Plug.Connection.Query.decode(query_string))
  end

  def fetch_params(Conn[params: _] = conn) do
    conn
  end
end
