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

  @doc """
  Puts a new request header.
  Previous entries of the same headers are removed.
  """
  @spec put_req_header(Conn.t, binary, binary) :: Conn.t
  def put_req_header(Conn[req_headers: headers] = conn, key, value) do
    conn.req_headers(:lists.keystore(key, 1, headers, { key, value }))
  end

  @doc """
  Deletes a request header.
  """
  @spec delete_req_header(Conn.t, binary) :: Conn.t
  def delete_req_header(Conn[req_headers: headers] = conn, key) do
    conn.req_headers(:lists.keydelete(key, 1, headers))
  end
end
