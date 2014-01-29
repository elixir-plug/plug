defmodule Plug.Head do
  @moduledoc """
  A Plug to convert "HEAD" requests to "GET".

  ## Examples

      Plug.Head.call(conn, [])
  """

  def call(conn, []) do
    if conn.method == "HEAD" do
      conn = conn.method("GET")
    end
    { :ok, conn }
  end
end
