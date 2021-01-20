defmodule Plug.Head do
  @moduledoc """
  A Plug to convert `HEAD` requests to `GET` requests.

  ## Examples

      Plug.Head.call(conn, [])
  """

  @behaviour Plug

  alias Plug.Conn

  @impl true
  def init([]), do: []

  @impl true
  def call(%Conn{method: "HEAD"} = conn, []), do: %{conn | method: "GET"}
  def call(conn, []), do: conn
end
