defmodule Plug.Parsers do
  defmodule RequestTooLargeError do
    @moduledoc """
    Error raised when the request is too large.
    """

    defexception message:
                   "the request is too large. If you are willing to process " <>
                     "larger requests, please give a :length to Plug.Parsers",
                 plug_status: 413
  end

  defmodule UnsupportedMediaTypeError do
    @moduledoc """
    Error raised when the request body cannot be parsed.
    """

    defexception media_type: nil, plug_status: 415

    def message(exception) do
      "unsupported media type #{exception.media_type}"
    end
  end

  defmodule BadEncodingError do
    @moduledoc """
    Raised when the request body contains bad encoding.
    """

    defexception message: nil, plug_status: 400
  end

  defmodule ParseError do
    @moduledoc """
    Error raised when the request body is malformed.
    """

    defexception exception: nil, plug_status: 400

    def message(%{exception: exception}) do
      "malformed request, a #{inspect(exception.__struct__)} exception was raised " <>
        "with message #{inspect(Exception.message(exception))}"
    end
  end

  @moduledoc """
  A plug for parsing the request body.

  It invokes a list of `:parsers`, which are activated based on the
  request content-type. Custom parsers are also supported by defining
  a module that implements the behaviour defined by this module.

  Once a connection goes through this plug, it will have `:body_params`
  set to the map of params parsed by one of the parsers listed in
  `:parsers` and `:params` set to the result of merging the `:body_params`
  and `:query_params`. In case `:query_params` have not yet been parsed,
  `Plug.Conn.fetch_query_params/2` is automatically invoked.

  This plug will raise `Plug.Parsers.UnsupportedMediaTypeError` by default if
  the request cannot be parsed by any of the given types and the MIME type has
  not been explicitly accepted with the `:pass` option.

  `Plug.Parsers.RequestTooLargeError` will be raised if the request goes over
  the given limit. The default length is 8MB and it can be customized by passing
  the `:length` option to the Plug. `:read_timeout` and `:read_length`, as
  described by `Plug.Conn.read_body/2`, are also supported.

  Parsers may raise a `Plug.Parsers.ParseError` if the request has a malformed
  body.

  This plug only parses the body if the request method is one of the following:

    * `POST`
    * `PUT`
    * `PATCH`
    * `DELETE`

  For requests with a different request method, this plug will only fetch the
  query params.

  ## Options

    * `:parsers` - a list of modules or atoms of built-in parsers to be
      invoked for parsing. These modules need to implement the behaviour
      outlined in this module.

    * `:pass` - an optional list of MIME type strings that are allowed
      to pass through. Any mime not handled by a parser and not explicitly
      listed in `:pass` will `raise UnsupportedMediaTypeError`. For example:

        * `["*/*"]` - never raises
        * `["text/html", "application/*"]` - doesn't raise for those values
        * `[]` - always raises (default)

    * `:query_string_length` - the maximum allowed size for query strings

    * `:validate_utf8` - boolean that tells whether or not we want to
        validate that parsed binaries are utf8 strings.

    * `:body_reader` - an optional replacement (or wrapper) for
      `Plug.Conn.read_body/2` to provide a function that gives access to the
      raw body before it is parsed and discarded. It is in the standard format
      of `{Module, :function, [args]}` (MFA) and defaults to
      `{Plug.Conn, :read_body, []}`. Note that this option is not used by
      `Plug.Parsers.MULTIPART` which relies instead on other functions defined
      in `Plug.Conn`.

  All other options given to this Plug are forwarded to the parsers.

  ## Examples

      plug Plug.Parsers,
           parsers: [:urlencoded, :multipart],
           pass: ["text/*"]

  Any other option given to Plug.Parsers is forwarded to the underlying
  parsers. Therefore, you can use a JSON parser and pass the `:json_decoder`
  option at the root:

      plug Plug.Parsers,
           parsers: [:urlencoded, :json],
           json_decoder: Jason

  Or directly to the parser itself:

      plug Plug.Parsers,
           parsers: [:urlencoded, {:json, json_decoder: Jason}]

  It is also possible to pass the `:json_decoder` as a `{module, function, args}` tuple,
  useful for passing options to the JSON decoder:

      plug Plug.Parsers,
           parsers: [:json],
           json_decoder: {Jason, :decode!, [[floats: :decimals]]}

  A common set of shared options given to Plug.Parsers is `:length`,
  `:read_length` and `:read_timeout`, which customizes the maximum
  request length you want to accept. For example, to support file
  uploads, you can do:

      plug Plug.Parsers,
           parsers: [:urlencoded, :multipart],
           length: 20_000_000

  However, the above will increase the maximum length of all request
  types. If you want to increase the limit only for multipart requests
  (which is typically the ones used for file uploads), you can do:

      plug Plug.Parsers,
           parsers: [
             :urlencoded,
             {:multipart, length: 20_000_000} # Increase to 20MB max upload
           ]

  ## Built-in parsers

  Plug ships with the following parsers:

    * `Plug.Parsers.URLENCODED` - parses `application/x-www-form-urlencoded`
      requests (can be used as `:urlencoded` as well in the `:parsers` option)
    * `Plug.Parsers.MULTIPART` - parses `multipart/form-data` and
      `multipart/mixed` requests (can be used as `:multipart` as well in the
      `:parsers` option)
    * `Plug.Parsers.JSON` - parses `application/json` requests with the given
      `:json_decoder` (can be used as `:json` as well in the `:parsers` option)

  ## File handling

  If a file is uploaded via any of the parsers, Plug will
  stream the uploaded contents to a file in a temporary directory in order to
  avoid loading the whole file into memory. For such, the `:plug` application
  needs to be started in order for file uploads to work. More details on how the
  uploaded file is handled can be found in the documentation for `Plug.Upload`.

  When a file is uploaded, the request parameter that identifies that file will
  be a `Plug.Upload` struct with information about the uploaded file (e.g.
  filename and content type) and about where the file is stored.

  The temporary directory where files are streamed to can be customized by
  setting the `PLUG_TMPDIR` environment variable on the host system. If
  `PLUG_TMPDIR` isn't set, Plug will look at some environment
  variables which usually hold the value of the system's temporary directory
  (like `TMPDIR` or `TMP`). If no value is found in any of those variables,
  `/tmp` is used as a default.

  ## Custom body reader

  Sometimes you may want to customize how a parser reads the body from the
  connection. For example, you may want to cache the body to perform verification
  later, such as HTTP Signature Verification. This can be achieved with a custom
  body reader that would read the body and store it in the connection, such as:

      defmodule CacheBodyReader do
        def read_body(conn, opts) do
          {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
          conn = update_in(conn.assigns[:raw_body], &[body | (&1 || [])])
          {:ok, body, conn}
        end
      end

  which could then be set as:

      plug Plug.Parsers,
        parsers: [:urlencoded, :json],
        pass: ["text/*"],
        body_reader: {CacheBodyReader, :read_body, []},
        json_decoder: Jason

  """

  alias Plug.Conn

  @callback init(opts :: Keyword.t()) :: Plug.opts()

  @doc """
  Attempts to parse the connection's request body given the content-type type,
  subtype, and its parameters.

  The arguments are:

    * the `Plug.Conn` connection
    * `type`, the content-type type (e.g., `"x-sample"` for the
      `"x-sample/json"` content-type)
    * `subtype`, the content-type subtype (e.g., `"json"` for the
      `"x-sample/json"` content-type)
    * `params`, the content-type parameters (e.g., `%{"foo" => "bar"}`
      for the `"text/plain; foo=bar"` content-type)

  This function should return:

    * `{:ok, body_params, conn}` if the parser is able to handle the given
      content-type; `body_params` should be a map
    * `{:next, conn}` if the next parser should be invoked
    * `{:error, :too_large, conn}` if the request goes over the given limit

  """
  @callback parse(
              conn :: Conn.t(),
              type :: binary,
              subtype :: binary,
              params :: Conn.Utils.params(),
              opts :: Plug.opts()
            ) ::
              {:ok, Conn.params(), Conn.t()}
              | {:error, :too_large, Conn.t()}
              | {:next, Conn.t()}

  @behaviour Plug
  @methods ~w(POST PUT PATCH DELETE)

  @impl true
  def init(opts) do
    {parsers, opts} = Keyword.pop(opts, :parsers)
    {pass, opts} = Keyword.pop(opts, :pass, [])
    {query_string_length, opts} = Keyword.pop(opts, :query_string_length, 1_000_000)
    validate_utf8 = Keyword.get(opts, :validate_utf8, true)

    unless parsers do
      raise ArgumentError, "Plug.Parsers expects a set of parsers to be given in :parsers"
    end

    {convert_parsers(parsers, opts), pass, query_string_length, validate_utf8}
  end

  defp convert_parsers(parsers, root_opts) do
    for parser <- parsers do
      {parser, opts} =
        case parser do
          {parser, opts} when is_atom(parser) and is_list(opts) ->
            {parser, Keyword.merge(root_opts, opts)}

          parser when is_atom(parser) ->
            {parser, root_opts}
        end

      module =
        case Atom.to_string(parser) do
          "Elixir." <> _ -> parser
          reference -> Module.concat(Plug.Parsers, String.upcase(reference))
        end

      # TODO: Remove this check in future releases once all parsers implement init/1 accordingly
      if Code.ensure_compiled(module) == {:module, module} and
           function_exported?(module, :init, 1) do
        {module, module.init(opts)}
      else
        {module, opts}
      end
    end
  end

  @impl true
  def call(%{method: method, body_params: %Plug.Conn.Unfetched{}} = conn, options)
      when method in @methods do
    {parsers, pass, query_string_length, validate_utf8} = options
    %{req_headers: req_headers} = conn

    conn =
      Conn.fetch_query_params(conn,
        length: query_string_length,
        validate_utf8: validate_utf8
      )

    case List.keyfind(req_headers, "content-type", 0) do
      {"content-type", ct} ->
        case Conn.Utils.content_type(ct) do
          {:ok, type, subtype, params} ->
            reduce(
              conn,
              parsers,
              type,
              subtype,
              params,
              pass,
              query_string_length,
              validate_utf8
            )

          :error ->
            reduce(conn, parsers, ct, "", %{}, pass, query_string_length, validate_utf8)
        end

      _ ->
        {conn, params} = merge_params(conn, %{}, query_string_length, validate_utf8)

        %{conn | params: params, body_params: %{}}
    end
  end

  def call(%{body_params: body_params} = conn, {_, _, query_string_length, validate_utf8}) do
    body_params = make_empty_if_unfetched(body_params)
    {conn, params} = merge_params(conn, body_params, query_string_length, validate_utf8)
    %{conn | params: params, body_params: body_params}
  end

  defp reduce(
         conn,
         [{parser, options} | rest],
         type,
         subtype,
         params,
         pass,
         query_string_length,
         validate_utf8
       ) do
    case parser.parse(conn, type, subtype, params, options) do
      {:ok, body, conn} ->
        {conn, params} = merge_params(conn, body, query_string_length, validate_utf8)
        %{conn | params: params, body_params: body}

      {:next, conn} ->
        reduce(conn, rest, type, subtype, params, pass, query_string_length, validate_utf8)

      {:error, :too_large, _conn} ->
        raise RequestTooLargeError
    end
  end

  defp reduce(conn, [], type, subtype, _params, pass, query_string_length, validate_utf8) do
    if accepted_mime?(type, subtype, pass) do
      {conn, params} = merge_params(conn, %{}, query_string_length, validate_utf8)
      %{conn | params: params}
    else
      raise UnsupportedMediaTypeError, media_type: "#{type}/#{subtype}"
    end
  end

  defp accepted_mime?(_type, _subtype, ["*/*"]),
    do: true

  defp accepted_mime?(type, subtype, pass),
    do: "#{type}/#{subtype}" in pass || "#{type}/*" in pass

  defp merge_params(conn, body_params, query_string_length, validate_utf8) do
    %{params: params, path_params: path_params} = conn
    params = make_empty_if_unfetched(params)

    conn =
      Plug.Conn.fetch_query_params(conn,
        length: query_string_length,
        validate_utf8: validate_utf8
      )

    {conn,
     conn.query_params
     |> Map.merge(params)
     |> Map.merge(body_params)
     |> Map.merge(path_params)}
  end

  defp make_empty_if_unfetched(%Plug.Conn.Unfetched{}), do: %{}
  defp make_empty_if_unfetched(params), do: params
end
