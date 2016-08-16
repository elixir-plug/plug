defmodule Plug.Session.ETS do
  @moduledoc """
  Stores the session in an in-memory ETS table.

  This store does not create the ETS table; it expects that an
  existing named table with public properties is passed as an
  argument.

  We don't recommend using this store in production as every
  session will be stored in ETS and never cleaned until you
  create a task responsible for cleaning up old entries.

  Also, since the store is in-memory, it means sessions are
  not shared between servers. If you deploy to more than one
  machine, using this store is again not recommended.

  This store, however, can be used as an example for creating
  custom storages, based on Redis, Memcached, or a database
  itself.

  ## Options

    * `:table` - ETS table name (required)
    * `:ttl` - The session expired seconds (optional)

  For more information on ETS tables, visit the Erlang documentation at
  http://www.erlang.org/doc/man/ets.html.

  ## Storage

  The data is stored in ETS in the following format:

      {sid :: String.t, data :: map, timestamp :: :erlang.timestamp}

  The timestamp is updated whenever there is a read or write to the
  table and it may be used to detect if a session is still active.

  ## Examples

      # Create an ETS table when the application starts
      :ets.new(:session, [:named_table, :public, read_concurrency: true])

      # Use the session plug with the table name
      plug Plug.Session, store: :ets, key: "sid", table: :session

      # Use the session plug with the table name and ttl
      plug Plug.Session, store: :ets, key: "sid", table: :session, ttl: 3600

  """

  @behaviour Plug.Session.Store

  @max_tries 100

  require Record
  Record.defrecordp :config, [
    ttl: nil,
    table: nil,
  ]

  def init(opts) do
    config(ttl: Keyword.get(opts, :ttl), table: Keyword.get(opts, :table))
  end

  def get(_conn, sid, config(ttl: ttl, table: table)) do
    case :ets.lookup(table, sid) do
      [result] ->
        check_result(ttl, table, result)
      [] ->
        {nil, %{}}
    end
  end

  def put(_conn, nil, data, config(ttl: _ttl, table: table)) do
    put_new(data, table)
  end

  def put(_conn, sid, data, config(ttl: _ttl, table: table)) do
    :ets.insert(table, {sid, data, now()})
    sid
  end

  def delete(_conn, sid, config(ttl: _ttl, table: table)) do
    :ets.delete(table, sid)
    :ok
  end

  defp put_new(data, table, counter \\ 0)
      when counter < @max_tries do
    sid = :crypto.strong_rand_bytes(96) |> Base.encode64

    if :ets.insert_new(table, {sid, data, now()}) do
      sid
    else
      put_new(data, table, counter + 1)
    end
  end

  defp now() do
    :os.timestamp()
  end

  defp is_expired?(:nil, _timestamp) do
    :false
  end
  defp is_expired?(ttl, {mega_secs, secs, micro_secs}) do
    {mega_secs, secs + ttl, micro_secs} < now()
  end

  defp check_result(ttl, table, {sid, data, timestamp}) do
    if is_expired?(ttl, timestamp) do
      :ets.delete(table, sid)
      {nil, %{}}
    else
      :ets.update_element(table, sid, {3, now()})
      {sid, data}
    end
  end
end
