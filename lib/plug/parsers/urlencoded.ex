defmodule Plug.Parsers.URLENCODED do
  @moduledoc false
  alias Plug.Conn

  def parse(%Conn{} = conn, "application", "x-www-form-urlencoded", _headers, opts) do
    read_body(conn, Keyword.fetch!(opts, :limit))
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp read_body(%Conn{adapter: {adapter, state}} = conn, limit) do
    case read_body({:ok, "", state}, "", limit, adapter) do
      {:too_large, state} ->
        {:too_large, %{conn | adapter: {adapter, state}}}
      {:ok, body, state} ->
        {:ok, Plug.Conn.Query.decode(body), %{conn | adapter: {adapter, state}}}
    end
  end

  defp read_body({:ok, buffer, state}, acc, limit, adapter) when limit >= 0,
    do: read_body(adapter.stream_req_body(state, 1_000_000), acc <> buffer, limit - byte_size(buffer), adapter)
  defp read_body({:ok, _, state}, _acc, _limit, _adapter),
    do: {:too_large, state}

  defp read_body({:done, state}, acc, limit, _adapter) when limit >= 0,
    do: {:ok, acc, state}
  defp read_body({:done, state}, _acc, _limit, _adapter),
    do: {:too_large, state}
end
