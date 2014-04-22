defmodule Plug.Parsers.MULTIPART do
  @moduledoc false
  alias Plug.Conn

  def parse(%Conn{} = conn, "multipart", subtype, _headers, opts) when subtype in ["form-data", "mixed"] do
    { adapter, state } = conn.adapter
    limit = Keyword.fetch!(opts, :limit)

    case adapter.parse_req_multipart(state, limit, &handle_headers/1) do
      { :ok, params, state } ->
        { :ok, params, %{conn | adapter: { adapter, state }} }
      { :too_large, state } ->
        { :too_large, %{conn | adapter: { adapter, state }} }
    end
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    { :next, conn }
  end

  defp handle_headers(headers) do
    case List.keyfind(headers, "content-disposition", 0) do
      { _, disposition } -> handle_disposition(disposition, headers)
      nil -> :skip
    end
  end

  defp handle_disposition(disposition, headers) do
    case :binary.split(disposition, ";") do
      [_, params] ->
        params = Plug.Conn.Utils.params(params)
        if name = params["name"] do
          handle_disposition_params(name, params, headers)
        else
          :skip
        end
      [_] ->
        :skip
    end
  end

  defp handle_disposition_params(name, params, headers) do
    if filename = params["filename"] do
      path = Plug.Upload.random_file!("multipart")
      file = File.open!(path, [:write, :binary])
      { :file, name, file, Plug.Upload.File[filename: filename, path: path,
                                            content_type: headers["content-type"]] }
    else
      { :binary, name }
    end
  end
end
