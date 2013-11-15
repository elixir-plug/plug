defrecord Plug.Conn,
    assigns: [], path_info: [], script_name: [], adapter: nil,
    host: nil, scheme: nil, port: nil, method: nil do

  @type assigns  :: Keyword.t
  @type segments :: [binary]
  @type adapter  :: { module, term }
  @type host     :: binary
  @type scheme   :: :http | :https
  @type port     :: 0..65535
  @type status   :: non_neg_integer
  @type headers  :: [{ binary, binary }]
  @type body     :: binary
  @type method   :: binary

  record_type assigns: assigns, path_info: segments, script_name: segments,
              adapter: adapter, host: host, scheme: scheme, port: port,
              method: method

  @moduledoc """
  The connection record.

  It is recommended to use the record for reading data,
  all connection manipulation should be done via the functions
  in `Plug.Connection` module.

  ## Fields

  Those fields can be accessed directly by the user.

  * `assigns` - store user data that is shared in the application code
  * `path_info` - path info information split into segments
  * `script_name` - script name information split into segments
  * `host` - the requested host
  * `port` - the requested port
  * `scheme` - the request scheme
  * `method` - the request method

  ## Private fields

  Those fields are reserved for libraries/framework usage.

  * `adapter` - holds the adapter information in a tuple
  """
end

defmodule Plug.Connection do
  @moduledoc """
  Functions for manipulating the connection.
  """

  alias Plug.Conn

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
  Sends to the client the given status and body.
  """
  @spec send(Conn.t, Conn.status, Conn.body) :: Conn.t
  def send(Conn[adapter: { adapter, payload }] = conn, status, body) when
      is_integer(status) and is_binary(body) do
    payload = adapter.send(payload, status, [], body)
    conn.adapter({ adapter, payload })
  end
end
