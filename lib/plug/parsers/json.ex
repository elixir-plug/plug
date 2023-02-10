defmodule Plug.Parsers.JSON do
  @moduledoc """
  Parses JSON request body.

  JSON documents that aren't maps (arrays, strings, numbers, etc) are parsed
  into a `"_json"` key to allow proper param merging.

  An empty request body is parsed as an empty map.

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

  The option `:nest_all_json`, when true, specifies all parsed JSON (including maps)
  are parsed into a `"_json"` key.
  """

  @behaviour Plug.Parsers

  @impl true
  def init(opts) do
    {decoder, opts} = Keyword.pop(opts, :json_decoder)
    {body_reader, opts} = Keyword.pop(opts, :body_reader, {Plug.Conn, :read_body, []})
    decoder = validate_decoder!(decoder)
    {body_reader, decoder, opts}
  end

  defp validate_decoder!(nil) do
    raise ArgumentError, "JSON parser expects a :json_decoder option"
  end

  defp validate_decoder!({module, fun, args} = mfa)
       when is_atom(module) and is_atom(fun) and is_list(args) do
    arity = length(args) + 1

    if Code.ensure_compiled(module) != {:module, module} do
      raise ArgumentError,
            "invalid :json_decoder option. The module #{inspect(module)} is not " <>
              "loaded and could not be found"
    end

    if not function_exported?(module, fun, arity) do
      raise ArgumentError,
            "invalid :json_decoder option. The module #{inspect(module)} must " <>
              "implement #{fun}/#{arity}"
    end

    mfa
  end

  defp validate_decoder!(decoder) when is_atom(decoder) do
    validate_decoder!({decoder, :decode!, []})
  end

  defp validate_decoder!(decoder) do
    raise ArgumentError,
          "the :json_decoder option expects a module, or a three-element " <>
            "tuple in the form of {module, function, extra_args}, got: #{inspect(decoder)}"
  end

  @impl true
  def parse(conn, "application", subtype, _headers, {{mod, fun, args}, decoder, opts}) do
    if subtype == "json" or String.ends_with?(subtype, "+json") do
      apply(mod, fun, [conn, opts | args]) |> decode(decoder, opts)
    else
      {:next, conn}
    end
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp decode({:ok, "", conn}, _decoder, _opts) do
    {:ok, %{}, conn}
  end

  defp decode({:ok, body, conn}, {module, fun, args}, opts) do
    nest_all = Keyword.get(opts, :nest_all_json, false)

    try do
      apply(module, fun, [body | args])
    rescue
      e -> raise Plug.Parsers.ParseError, exception: e
    else
      terms when is_map(terms) and not nest_all ->
        {:ok, terms, conn}

      terms ->
        {:ok, %{"_json" => terms}, conn}
    end
  end

  defp decode({:more, _, conn}, _decoder, _opts) do
    {:error, :too_large, conn}
  end

  defp decode({:error, :timeout}, _decoder, _opts) do
    raise Plug.TimeoutError
  end

  defp decode({:error, _}, _decoder, _opts) do
    raise Plug.BadRequestError
  end
end
