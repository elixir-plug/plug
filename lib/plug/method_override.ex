defmodule Plug.MethodOverride do
  @moduledoc """
  A plug to overwrite "POST" method with the one defined in _method parameter
  or x-http-method-override header.

  This plug expects the parameters to be already parsed and fetched.

  ## Examples

      Plug.MethodOverride.call(conn, [])
  """

  def call(conn, []) do
    if conn.method == "POST" do
      case method_override(conn) do
        "DELETE" -> { :ok, conn.method("DELETE") }
        "PUT"    -> { :ok, conn.method("PUT") }
        "PATCH"  -> { :ok, conn.method("PATCH") }
        _        -> { :ok, conn }
      end
    else
      { :ok, conn }
    end
  end

  defp method_override(Plug.Conn[req_headers: req_headers] = conn) do
    conn.params["_method"] || req_headers["x-http-method-override"]
  end
end
