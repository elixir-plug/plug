defmodule Plug.Parsers.URLENCODED do
  @moduledoc false
  alias Plug.Conn

  def parse(Conn[] = conn, "application", "x-www-form-urlencoded", _headers, opts) do
    { conn, body } = read_body(conn, Keyword.get!(opts, :limit))
    { :ok, conn.params(Plug.Connection.Query.decode(body, conn.params)) }
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    { :halt, conn }
  end

  defp read_body(Conn[adapter: { adapter, state }] = conn, limit) do
    case read_body({ :ok, "", state }, "", limit, adapter) do
      { :too_large, state } ->
        raise Plug.Parsers.RequestTooLargeError, conn: conn.adapter({ adapter, state })
      { body, state } ->
        { conn.adapter({ adapter, state }), body }
    end
  end

  defp read_body({ :ok, buffer, state }, acc, limit, adapter) when limit >= 0,
    do: read_body(adapter.stream_req_body(state, 1_000_000), acc <> buffer, limit - byte_size(buffer), adapter)
  defp read_body({ :ok, _, state }, _acc, _limit, _adapter),
    do: { :too_large, state }

  defp read_body({ :done, state }, acc, limit, _adapter) when limit >= 0,
    do: { acc, state }
  defp read_body({ :done, state }, _acc, _limit, _adapter),
    do: { :too_large, state }
end
