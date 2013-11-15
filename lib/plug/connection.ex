defrecord Plug.Conn, assigns: [], path_info: [], script_name: [], adapter: nil do
  @type assigns  :: Keyword.t
  @type segments :: [binary]
  @type adapter  :: { module, term }

  record_type assigns: assigns,
              path_info: segments,
              script_name: segments,
              adapter: adapter

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

  ## Private fields

  Those fields are reserved for lbiraries/framework usage.

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

  """
  @spec assign(Conn.t, atom, term) :: Conn.t
  def assign(Conn[assigns: assigns] = conn, key, value) when is_atom(key) do
    conn.assigns(Keyword.put(assigns, key, value))
  end
end
