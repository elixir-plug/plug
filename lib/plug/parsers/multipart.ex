defmodule Plug.Parsers.MULTIPART do
  @moduledoc """
  Parses multipart request body.
  """

  @behaviour Plug.Parsers

  def parse(conn, "multipart", subtype, _headers, opts) when subtype in ["form-data", "mixed"] do
    {adapter, state} = conn.adapter

    case adapter.parse_req_multipart(state, opts, &handle_headers/1) do
      {:ok, params, state} ->
        {:ok, params, %{conn | adapter: {adapter, state}}}
      {:more, _params, state} ->
        {:error, :too_large, %{conn | adapter: {adapter, state}}}
    end
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp handle_headers(headers) do
    case List.keyfind(headers, "content-disposition", 0) do
      {_, disposition} -> handle_disposition(disposition, headers)
      nil -> :skip
    end
  end

  defp handle_disposition(disposition, headers) do
    case :binary.split(disposition, ";") do
      [_, params] ->
        params = Plug.Conn.Utils.params(params)
        if name = Map.get(params, "name") do
          handle_disposition_params(name, params, headers)
        else
          :skip
        end
      [_] ->
        :skip
    end
  end

  defp handle_disposition_params(name, params, headers) do
    if filename = Map.get(params, "filename") do
      path = Plug.Upload.random_file!("multipart")
      file = File.open!(path, [:write, :binary])
      {:file, name, file, %Plug.Upload{filename: filename, path: path,
                                       content_type: get_header(headers, "content-type")}}
    else
      {:binary, name}
    end
  end

  defp get_header(headers, key) do
    case List.keyfind(headers, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end
end
