defmodule Plug.Parsers.JSON do
  @moduledoc """
  Parses JSON request body
  """

  import Plug.Conn

  @doc """
  Parses JSON body into `conn.params`

  JSON arrays are parsed into a `"_json"` key to allow
  proper param merging.

  An empty request body is parsed as an empty map.
  """
  def parse(conn, "application", "json", _headers, opts) do
    decoder = Keyword.get(opts, :json_decoder) ||
                raise ArgumentError, "JSON parser expects a :json_decoder option"
    conn
    |> read_body(opts)
    |> decode(decoder)
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp decode({:more, _, conn}, _decoder) do
    {:error, :too_large, conn}
  end

  defp decode({:ok, "", conn}, _decoder) do
    {:ok, %{}, conn}
  end

  defp decode({:ok, body, conn}, decoder) do
    case decoder.decode(body) do
      {:ok, terms} when is_list(terms)->
        {:ok, %{"_json" => terms}, conn}
      {:ok, terms} ->
        {:ok, terms, conn}
      _ ->
        raise Plug.Parsers.ParseError, message: "malformed JSON"
    end
  end
end
