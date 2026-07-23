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

  @decoder_key {__MODULE__, :decoder}
  @body_reader_key {__MODULE__, :body_reader}

  @impl true
  def init(opts) do
    {decoder, opts} = Keyword.pop(opts, :json_decoder)
    {body_reader, opts} = Keyword.pop(opts, :body_reader, {Plug.Conn, :read_body, []})

    decoder_fun = build_decoder_fun(validate_decoder!(decoder))
    body_reader_fun = build_body_reader_fun(validate_body_reader!(body_reader))

    :persistent_term.put(@decoder_key, decoder_fun)
    :persistent_term.put(@body_reader_key, body_reader_fun)

    nest_all = Keyword.get(opts, :nest_all_json, false)

    {nest_all, opts}
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

  defp validate_decoder!(module) when is_atom(module) do
    ensure_compiled_and_exported(module, :decode!, 1)
  end

  defp validate_decoder!(other) do
     raise ArgumentError,
          "the :json_decoder option expects a module, or a three-element " <>
            "tuple in the form of {module, function, extra_args}, got: #{inspect(other)}"
  end

  defp validate_body_reader!({module, fun, args} = mfa)
       when is_atom(module) and is_atom(fun) and is_list(args) do
    ensure_compiled_and_exported(module, fun, length(args) + 2)
    mfa
  end

  defp ensure_compiled_and_exported(module, fun, arity) do
    if Code.ensure_compiled(module) != {:module, module} do
      raise ArgumentError,
            "invalid :json_decoder option. The module #{inspect(module)} is not " <>
              "loaded and could not be found"
    end

    if function_exported?(module, fun, arity) do
      module
    else
      raise ArgumentError,
            "invalid :json_decoder option. The module #{inspect(module)} must implement #{fun}/#{arity}"
    end
  end

  # Fast path: module.decode!/1
  defp build_decoder_fun(module) when is_atom(module) do
    fn body -> module.decode!(body) end
  end

  # MFA path: apply(module, fun, [body | args])
  defp build_decoder_fun({module, fun, args}) do
    fn body ->
      apply(module, fun, [body | args])
    end
  end

  defp build_body_reader_fun({module, fun, args}) do
    fn conn, opts ->
      apply(module, fun, [conn, opts | args])
    end
  end

  @impl true
  def parse(conn, "application", subtype, _headers, {nest_all, opts})
      when subtype == "json" or binary_part(subtype, byte_size(subtype) - 5, 5) == "+json" do

    body_reader_fun = :persistent_term.get(@body_reader_key)

    case body_reader_fun.(conn, opts) do
      {:ok, "", conn} ->
        {:ok, %{}, conn}

      {:ok, body, conn} ->
        decode_body(body, conn, nest_all)

      {:more, _, conn} ->
        {:error, :too_large, conn}

      {:error, :timeout} ->
        raise Plug.TimeoutError

      {:error, _} ->
        raise Plug.BadRequestError
    end
  end

  def parse(conn, _type, _subtype, _headers, _state) do
    {:next, conn}
  end

  defp decode_body(body, conn, nest_all) do
    decoder_fun = :persistent_term.get(@decoder_key)

    try do
      terms = decoder_fun.(body)

      cond do
        is_map(terms) and not nest_all ->
          {:ok, terms, conn}

        true ->
          {:ok, %{"_json" => terms}, conn}
      end
    rescue
      e ->
        raise Plug.Parsers.ParseError, exception: e
    end
  end
end
