defmodule Plug.MethodOverride do
  @moduledoc """
  A plug to overwrite "POST" method with the one defined in _method parameter
  or x-http-method-override header.

  This plug expects the parameters to be already parsed and fetched. Parameters
  are fetched with `Plug.Conn.fetch_params/1` and parsed with
  `Plug.Parsers`.

  ## Examples

      Plug.MethodOverride.call(conn, [])
  """

  @behaviour Plug

  def init([]) do
    []
  end

  def call(conn, []) do
    if conn.method == "POST" do
      case method_override(conn) do
        "DELETE" -> %{conn | method: "DELETE"}
        "PUT"    -> %{conn | method: "PUT"}
        "PATCH"  -> %{conn | method: "PATCH"}
        _        -> conn
      end
    else
      conn
    end
  end

  defp method_override(conn) do
    conn.params["_method"] ||
      (Plug.Conn.get_req_header(conn, "x-http-method-override") |> List.first)
  end
end
