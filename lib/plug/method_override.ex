defmodule Plug.MethodOverride do
  @moduledoc """
  This plug overrides the request's `POST` method with the method defined in
  the `_method` request parameter.

  The `POST` method can be overridden only by these HTTP methods:

    * `PUT`
    * `PATCH`
    * `DELETE`

  This plug only replaces the request method if the `_method` request
  parameter is a string. If the `_method` request parameter is not a string,
  the request method is not changed.

  > #### Parse Body Parameters First {: .info}
  >
  > This plug expects the body parameters to be **already fetched and
  > parsed**. Those can be fetched with `Plug.Parsers`.

  This plug doesn't accept any options.

  To recap, here are all the conditions that the request must meet in order
  for this plug to replace the `:method` field in the `Plug.Conn`:

    1. The conn's request `:method` must be `POST`.
    1. The conn's `:body_params` must have been fetched already (for example,
       with `Plug.Parsers`).
    1. The conn's `:body_params` must have a `_method` field that is a string
       and whose value is `"PUT"`, `"PATCH"`, or `"DELETE"` (case insensitive).

  ## Usage

      # You'll need to fetch and parse parameters first, for example:
      # plug Plug.Parsers, parsers: [:urlencoded, :multipart, :json]

      plug Plug.MethodOverride

  """

  @behaviour Plug

  @allowed_methods ~w(DELETE PUT PATCH)

  @impl true
  def init([]), do: []

  @impl true
  def call(%Plug.Conn{method: "POST", body_params: body_params} = conn, []),
    do: override_method(conn, body_params)

  def call(%Plug.Conn{} = conn, []), do: conn

  defp override_method(conn, %Plug.Conn.Unfetched{}) do
    # Just skip it because maybe it is a content-type that
    # we could not parse as parameters (for example, text/gps)
    conn
  end

  defp override_method(%Plug.Conn{} = conn, body_params) do
    with method when is_binary(method) <- body_params["_method"] || "",
         method = String.upcase(method, :ascii),
         true <- method in @allowed_methods do
      %{conn | method: method}
    else
      _ -> conn
    end
  end
end
