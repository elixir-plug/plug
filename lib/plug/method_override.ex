defmodule Plug.MethodOverride do
  @moduledoc """
  This plug overrides the request's `POST` method with the method defined in
  the `_method` request parameter.

  The `POST` method can be overridden only with on of these HTTP methods:

  * `PUT`
  * `PATCH`
  * `DELETE`

  This plug expects the parameters to be already parsed and fetched. Parameters
  are fetched with `Plug.Conn.fetch_params/1` and parsed with `Plug.Parsers`.

  This plug doesn't accept any options.

  ## Examples

      Plug.MethodOverride.call(conn, [])
  """

  @behaviour Plug

  @allowed_methods ~w(DELETE PUT PATCH)

  def init([]), do: []

  def call(conn, []) do
    if conn.method == "POST" do
      override_method(conn)
    else
      conn
    end
  end

  @spec override_method(Plug.Conn.t) :: Plug.Conn.t
  defp override_method(conn) do
    method = (conn.params["_method"] || "") |> String.upcase

    cond do
      method in @allowed_methods -> %{conn | method: method}
      true                       -> conn
    end
  end
end
