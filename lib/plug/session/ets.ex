defmodule Plug.Session.ETS do
  @moduledoc """
  Stores the session in an in-memory ETS table.

  This store does not create the ETS table; it expects that an existing named
  table with public properties is passed as an argument.

  ## Options

  * `:table` - ETS table name (required)

  For more information on ETS tables, visit the Erlang documentation at
  http://www.erlang.org/doc/man/ets.html.

  ## Examples

      # Create an ETS table when the application starts
      :ets.new(:session, [:named_table, :public, read_concurrency: true])

      # Use the session plug with the table name
      plug Plug.Session, store: :ets, key: "sid", table: :session

  """

  @behaviour Plug.Session.Store

  @max_tries 100

  def init(opts) do
    Keyword.fetch!(opts, :table)
  end

  def get(_conn, sid, table) do
    case :ets.lookup(table, sid) do
      [{^sid, data}] -> {sid, data}
      [] -> {nil, %{}}
    end
  end

  def put(_conn, nil, data, table) do
    put_new(data, table)
  end

  def put(_conn, sid, data, table) do
    :ets.insert(table, {sid, data})
    sid
  end

  def delete(_conn, sid, table) do
    :ets.delete(table, sid)
    :ok
  end

  defp put_new(data, table, counter \\ 0)
      when counter < @max_tries do
    sid = :crypto.strong_rand_bytes(96) |> Base.encode64

    if :ets.insert_new(table, {sid, data}) do
      sid
    else
      put_new(data, table, counter + 1)
    end
  end
end
