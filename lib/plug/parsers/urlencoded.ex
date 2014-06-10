defmodule Plug.Parsers.URLENCODED do
  @moduledoc false
  alias Plug.Conn

  def parse(%Conn{} = conn, "application", "x-www-form-urlencoded", _headers, opts) do
    case Conn.collect_body(conn, "", opts) do
      {:ok, body, conn} ->
        {:ok, Plug.Conn.Query.decode(body), conn}
      {:error, :too_large, conn} ->
        {:error, :too_large, conn}
    end
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end
end
