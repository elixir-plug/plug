defmodule Plug.Test do
  @moduledoc """
  Conveniences for testing plugs.
  """

  alias Plug.Conn

  @doc """
  Creates a test connection.
  """
  @spec conn(atom | binary, binary) :: Conn.t
  def conn(method, path) do
    Plug.Adapters.Test.Connection.conn(method, path)
  end

  @doc """
  Returns the body sent during testing.
  """
  @spec sent_body(Conn.t) :: Conn.body | nil
  def sent_body(Conn[adapter: { Plug.Adapters.Test.Connection, { _, body } }]) do
    body
  end
end
