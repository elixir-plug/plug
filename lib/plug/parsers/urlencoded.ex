defmodule Plug.Parsers.URLENCODED do
  @moduledoc false
  alias Plug.Conn

  def parse(%Conn{} = conn, "application", "x-www-form-urlencoded", _headers, opts) do
    read_body(conn, Keyword.fetch!(opts, :limit))
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end
end
