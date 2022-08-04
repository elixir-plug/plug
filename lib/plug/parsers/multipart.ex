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
  also checks for:

    * `:headers` - containing the same `:length`, `:read_length`
      and `:read_timeout` options which are used explicitly for parsing multipart
      headers

    * `:validate_utf8` - specifies whether multipart body parts should be validated
      as utf8 binaries. Defaults to true

    * `:multipart_to_params` - a MFA that receives the multipart headers and the
      connection and it must return a tuple of `{:ok, params, conn}`

  ## Multipart to params

  Once all multiparts are collected, they must be converted to params and this
  can be customize with a MFA. The default implementation of this function
  is equivalent to:

      def multipart_to_params(parts, conn) do
        params =
          for {name, _headers, body} <- parts,
              name != nil,
              reduce: %{} do
            acc -> Plug.Conn.Query.decode_pair({name, body}, acc)
          end

        {:ok, params, conn}
      end

  As you can notice, it discards all multiparts without a name. If you want
  to keep the unnamed parts, you can store all of them under a known prefix,
  such as:

      def multipart_to_params(parts, conn) do
        params =
          for {name, _headers, body} <- parts, reduce: %{} do
            acc -> Plug.Conn.Query.decode_pair({name || "_parts[]", body}, acc)
          end

        {:ok, params, conn}
      end

  ## Dynamic configuration

  If you need to dynamically configure how `Plug.Parsers.MULTIPART` behave,
  for example, based on the connection or another system parameter, one option
  is to create your own parser that wraps it:

      defmodule MyMultipart do
        @multipart Plug.Parsers.MULTIPART

        def init(opts) do
          opts
        end

        def parse(conn, "multipart", subtype, headers, opts) do
          length = System.fetch_env!("UPLOAD_LIMIT") |> String.to_integer
          opts = @multipart.init([length: length] ++ opts)
          @multipart.parse(conn, "multipart", subtype, headers, opts)
        end

        def parse(conn, _type, _subtype, _headers, _opts) do
          {:next, conn}
        end
      end

  """

  @behaviour Plug.Parsers

  @impl true
  def init(opts) do
    # Remove the length from options as it would attempt
    # to eagerly read the body on the limit value.
    {limit, opts} = Keyword.pop(opts, :length, 8_000_000)

    # The read length is now our effective length per call.
    {read_length, opts} = Keyword.pop(opts, :read_length, 1_000_000)
    opts = [length: read_length, read_length: read_length] ++ opts

    # The header options are handled individually.
    {headers_opts, opts} = Keyword.pop(opts, :headers, [])

    with {_, _, _} <- limit do
      IO.warn(
        "passing a {module, function, args} tuple to Plug.Parsers.MULTIPART is deprecated. " <>
          "Please see Plug.Parsers.MULTIPART module docs for better approaches to configuration"
      )
    end

    if opts[:include_unnamed_parts_at] do
      IO.warn(
        ":include_unnamed_parts_at for multipart is deprecated. Use :multipart_to_params instead"
      )
    end

    m2p = opts[:multipart_to_params] || {__MODULE__, :multipart_to_params, [opts]}
    {m2p, limit, headers_opts, opts}
  end

  @impl true
  def parse(conn, "multipart", subtype, _headers, opts_tuple)
      when subtype in ["form-data", "mixed"] do
    try do
      parse_multipart(conn, opts_tuple)
    rescue
      # Do not ignore upload errors
      e in [Plug.UploadError, Plug.Parsers.BadEncodingError] ->
        reraise e, __STACKTRACE__

      # All others are wrapped
      e ->
        reraise Plug.Parsers.ParseError.exception(exception: e), __STACKTRACE__
    end
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  @doc false
  def multipart_to_params(acc, conn, opts) do
    unnamed_at = opts[:include_unnamed_parts_at]

    params =
      Enum.reduce(acc, %{}, fn
        {nil, headers, body}, acc when unnamed_at != nil ->
          Plug.Conn.Query.decode_pair(
            {unnamed_at <> "[]", %{headers: headers, body: body}},
            acc
          )

        {nil, _headers, _body}, acc ->
          acc

        {name, _headers, body}, acc ->
          Plug.Conn.Query.decode_pair({name, body}, acc)
      end)

    {:ok, params, conn}
  end

  ## Multipart

  defp parse_multipart(conn, {m2p, {module, fun, args}, header_opts, opts}) do
    # TODO: This is deprecated. Remove me on Plug 2.0.
    limit = apply(module, fun, args)
    parse_multipart(conn, {m2p, limit, header_opts, opts})
  end

  defp parse_multipart(conn, {m2p, limit, headers_opts, opts}) do
    read_result = Plug.Conn.read_part_headers(conn, headers_opts)
    {:ok, limit, acc, conn} = parse_multipart(read_result, limit, opts, headers_opts, [])

    if limit > 0 do
      {mod, fun, args} = m2p
      apply(mod, fun, [acc, conn | args])
    else
      {:error, :too_large, conn}
    end
  end

  defp parse_multipart({:ok, headers, conn}, limit, opts, headers_opts, acc) when limit >= 0 do
    {conn, limit, acc} = parse_multipart_headers(headers, conn, limit, opts, acc)
    read_result = Plug.Conn.read_part_headers(conn, headers_opts)
    parse_multipart(read_result, limit, opts, headers_opts, acc)
  end

  defp parse_multipart({:ok, _headers, conn}, limit, _opts, _headers_opts, acc) do
    {:ok, limit, acc, conn}
  end

  defp parse_multipart({:done, conn}, limit, _opts, _headers_opts, acc) do
    {:ok, limit, acc, conn}
  end

  defp parse_multipart_headers(headers, conn, limit, opts, acc) do
    case multipart_type(headers) do
      {:binary, name} ->
        {:ok, limit, body, conn} =
          parse_multipart_body(Plug.Conn.read_part_body(conn, opts), limit, opts, "")

        if Keyword.get(opts, :validate_utf8, true) do
          Plug.Conn.Utils.validate_utf8!(body, Plug.Parsers.BadEncodingError, "multipart body")
        end

        {conn, limit, [{name, headers, body} | acc]}

      {:file, name, path, %Plug.Upload{} = uploaded} ->
        {:ok, file} = File.open(path, [:write, :binary, :delayed_write, :raw])

        {:ok, limit, conn} =
          parse_multipart_file(Plug.Conn.read_part_body(conn, opts), limit, opts, file)

        :ok = File.close(file)
        {conn, limit, [{name, headers, uploaded} | acc]}

      :skip ->
        {conn, limit, acc}
    end
  end

  defp parse_multipart_body({:more, tail, conn}, limit, opts, body)
       when limit >= byte_size(tail) do
    read_result = Plug.Conn.read_part_body(conn, opts)
    parse_multipart_body(read_result, limit - byte_size(tail), opts, body <> tail)
  end

  defp parse_multipart_body({:more, tail, conn}, limit, _opts, body) do
    {:ok, limit - byte_size(tail), body, conn}
  end

  defp parse_multipart_body({:ok, tail, conn}, limit, _opts, body)
       when limit >= byte_size(tail) do
    {:ok, limit - byte_size(tail), body <> tail, conn}
  end

  defp parse_multipart_body({:ok, tail, conn}, limit, _opts, body) do
    {:ok, limit - byte_size(tail), body, conn}
  end

  defp parse_multipart_file({:more, tail, conn}, limit, opts, file)
       when limit >= byte_size(tail) do
    binwrite!(file, tail)
    read_result = Plug.Conn.read_part_body(conn, opts)
    parse_multipart_file(read_result, limit - byte_size(tail), opts, file)
  end

  defp parse_multipart_file({:more, tail, conn}, limit, _opts, _file) do
    {:ok, limit - byte_size(tail), conn}
  end

  defp parse_multipart_file({:ok, tail, conn}, limit, _opts, file)
       when limit >= byte_size(tail) do
    binwrite!(file, tail)
    {:ok, limit - byte_size(tail), conn}
  end

  defp parse_multipart_file({:ok, tail, conn}, limit, _opts, _file) do
    {:ok, limit - byte_size(tail), conn}
  end

  ## Helpers

  defp binwrite!(device, contents) do
    case IO.binwrite(device, contents) do
      :ok ->
        :ok

      {:error, reason} ->
        raise Plug.UploadError,
              "could not write to file #{inspect(device)} during upload " <>
                "due to reason: #{inspect(reason)}"
    end
  end

  defp multipart_type(headers) do
    with {_, disposition} <- List.keyfind(headers, "content-disposition", 0),
         [_, params] <- :binary.split(disposition, ";"),
         %{"name" => name} = params <- Plug.Conn.Utils.params(params) do
      handle_disposition(params, name, headers)
    else
      _ -> {:binary, nil}
    end
  end

  defp handle_disposition(params, name, headers) do
    case params do
      %{"filename" => ""} ->
        :skip

      %{"filename" => filename} ->
        path = Plug.Upload.random_file!("multipart")
        content_type = get_header(headers, "content-type")
        upload = %Plug.Upload{filename: filename, path: path, content_type: content_type}
        {:file, name, path, upload}

      %{"filename*" => ""} ->
        :skip

      %{"filename*" => "utf-8''" <> filename} ->
        filename = URI.decode(filename)

        Plug.Conn.Utils.validate_utf8!(
          filename,
          Plug.Parsers.BadEncodingError,
          "multipart filename"
        )

        path = Plug.Upload.random_file!("multipart")
        content_type = get_header(headers, "content-type")
        upload = %Plug.Upload{filename: filename, path: path, content_type: content_type}
        {:file, name, path, upload}

      %{} ->
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
