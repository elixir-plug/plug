defmodule Plug.Head do
  @moduledoc """
  A Plug to convert "HEAD" requests to "GET".

  ## Examples

      Plug.Head.call(conn, [])
  """

  @behaviour Plug

  def init([]) do
    []
  end

  def call(conn, []) do
    if conn.method == "HEAD" do
      %{conn | method: "GET"}
    else
      conn
    end
  end
end
