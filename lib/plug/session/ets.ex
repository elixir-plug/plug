defmodule Plug.Session.ETS do
  @moduledoc """
  Stores the session in an in-memory ETS table.

  A created ETS table is required for this store to work.

  This store does not create the ETS table, it is expected
  that an existing named table is given as argument with
  public properties.

  ## Options

  * `:table` - ETS table name (required);

  ## Examples

      # Create table during application start
      :ets.new(:session, [:named_table, :public, read_concurrency: true])

      # Use the session plug with the table name
      plug Plug.Session, store: :ets, key: "sid", table: :session

  http://www.erlang.org/doc/man/ets.html
  """

  @behaviour Plug.Session.Store

  @max_tries 100

  defrecordp :config, [:table]

  def init(opts) do
    table = Keyword.fetch!(opts, :table)
    config(table: table)
  end

  def get(sid, config(table: table)) do
    case :ets.lookup(table, sid) do
      [{ ^sid, data }] -> { sid, data }
      [] -> { nil, nil }
    end
  end

  def put(nil, data, config) do
    sid = generate_sid(config)
    put(sid, data, config)
  end

  def put(sid, data, config(table: table)) do
    :ets.insert(table, { sid, data })
    sid
  end

  def delete(sid, config(table: table)) do
    :ets.delete(table, sid)
    :ok
  end

  defp generate_sid(config = config(table: table), counter \\ 0)
      when counter < @max_tries do
    sid = :crypto.strong_rand_bytes(96) |> :base64.encode

    if :ets.insert_new(table, sid) do
      sid
    else
      generate_sid(config, counter + 1)
    end
  end
end
