defmodule Plug.Parsers.MULTIPART do
  @moduledoc """
  Parses multipart request body.

  ## Options

  All options supported by `Plug.Conn.read_body/2` are also supported here.
  They are repeated here for convenience:

    * `:length` - sets the maximum number of bytes to read from the request,
      defaults to 8_000_000 bytes
    * `:read_length` - sets the amount of bytes to read at one time from the
      underlying socket to fill the chunk, defaults to 1_000_000 bytes
    * `:read_timeout` - sets the timeout for each socket read, defaults to
      15_000ms

  So by default, `Plug.Parsers` will read 1_000_000 bytes at a time from the
  socket with an overall limit of 8_000_000 bytes.

  Besides the options supported by `Plug.Conn.read_body/2`, the multipart parser
  also checks for `:headers` option that contains the same `:length`, `:read_length`
  and `:read_timeout` options which are used explicitly for parsing multipart
  headers.
  """

  @behaviour Plug.Parsers

  def init(opts) do
    opts
  end

  def parse(conn, "multipart", subtype, _headers, opts) when subtype in ["form-data", "mixed"] do
    {adapter, state} = conn.adapter

    try do
      adapter.parse_req_multipart(state, opts, &handle_headers/1)
    rescue
      e in Plug.UploadError -> # Do not ignore upload errors
        reraise e, System.stacktrace
      e -> # All others are wrapped
        reraise Plug.Parsers.ParseError.exception(exception: e), System.stacktrace
    else
      {:ok, params, state} ->
        {:ok, params, %{conn | adapter: {adapter, state}}}
      {:more, _params, state} ->
        {:error, :too_large, %{conn | adapter: {adapter, state}}}
      {:error, :timeout} ->
        raise Plug.TimeoutError
      {:error, _} ->
        raise Plug.BadRequestError
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
    case Map.get(params, "filename") do
      nil      -> {:binary, name}
      ""       -> :skip
      filename ->
        path = Plug.Upload.random_file!("multipart")
        {:file, name, path, %Plug.Upload{filename: filename, path: path,
                                         content_type: get_header(headers, "content-type")}}
    end
  end

  defp get_header(headers, key) do
    case List.keyfind(headers, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end
end
