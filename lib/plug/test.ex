defmodule Plug.Test do
  @moduledoc """
  Conveniences for testing plugs.
  """

  alias Plug.Conn

  @doc """
  Creates a test connection.
  """
  @spec conn(atom | binary, binary, binary | list, Keyword.t) :: Conn.t
  def conn(method, path, params_or_body // [], opts // []) do
    Plug.Adapters.Test.Connection.conn(method, path, params_or_body, opts)
  end

  @doc """
  Returns the body sent during testing.
  """
  @spec sent_body(Conn.t) :: Conn.body | nil
  def sent_body(Conn[adapter: { Plug.Adapters.Test.Connection, state }]) do
    Plug.Adapters.Test.Connection.sent_body(state)
  end
end
