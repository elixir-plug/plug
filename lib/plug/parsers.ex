defmodule Plug.Parsers do
  defmodule RequestTooLargeError do
    @moduledoc """
    Error raised when the request is too large.
    """

    defexception message: "the request is too large. If you are willing to process " <>
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

    defexception message: nil, plug_status: 415
  end

  defmodule ParseError do
    @moduledoc """
    Error raised when the request body is malformed.
    """

    defexception exception: nil, plug_status: 400

    def message(exception) do
      exception = exception.exception
      "malformed request, got #{inspect exception.__struct__} " <>
        "with message #{Exception.message(exception)}"
    end
  end

  @moduledoc """
  A plug for parsing the request body.

  This module also specifies a behaviour that all the parsers to be used with
  Plug should adopt.

  ## Options

    * `:parsers` - a set of modules to be invoked for parsing.
      These modules need to implement the behaviour outlined in
      this module.

    * `:pass` - an optional list of MIME type strings that are allowed
      to pass through. Any mime not handled by a parser and not explicitly
      listed in `:pass` will `raise UnsupportedMediaTypeError`. For example:

        * `["*/*"]` - never raises
        * `["text/html", "application/*"]` - doesn't raise for those values
        * `[]` - always raises (default)

  All options supported by `Plug.Conn.read_body/2` are also supported here (for
  example the `:length` option which specifies the max body length to read).

  ## Examples

      plug Plug.Parsers, parsers: [:urlencoded, :multipart]
      plug Plug.Parsers, parsers: [:urlencoded, :json],
                         pass:  ["text/*"],
                         json_decoder: Poison

  ## Built-in parsers

  Plug ships with the following parsers:

  * `Plug.Parsers.URLENCODED` - parses `application/x-www-form-urlencoded`
    requests
  * `Plug.Parsers.MULTIPART` - parses `multipart/form-data` and
    `multipart/mixed` requests
  * `Plug.Parsers.JSON` - parses `application/json` requests with the given
    `:json_decoder`

  This plug will raise `Plug.Parsers.UnsupportedMediaTypeError` by default if
  the request cannot be parsed by any of the given types and the MIME type has
  not been explicity accepted with the `:pass` option.

  `Plug.Parsers.RequestTooLargeError` will be raised if the request goes over
  the given limit.

  Parsers may raise a `Plug.Parsers.ParseError` if the request has a malformed
  body.

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
  """

  alias Plug.Conn
  use Behaviour

  @doc """
  Attempts to parse the connection's request body given the content-type type
  and subtype and the headers. Returns:

    * `{:ok, conn}` if the parser is able to handle the given content-type
    * `{:next, conn}` if the next parser should be invoked
    * `{:error, :too_large, conn}` if the request goes over the given limit

  """
  defcallback parse(Conn.t, type :: binary, subtype :: binary,
                    headers :: Keyword.t, opts :: Keyword.t) ::
                    {:ok, Conn.params, Conn.t} |
                    {:error, :too_large, Conn.t} |
                    {:next, Conn.t}

  @behaviour Plug
  @methods ~w(POST PUT PATCH DELETE)

  def init(opts) do
    parsers = Keyword.get(opts, :parsers) || raise_missing_parsers

    opts
    |> Keyword.put(:parsers, convert_parsers(parsers))
    |> Keyword.put_new(:length, 8_000_000)
    |> Keyword.put_new(:pass, [])
  end

  defp raise_missing_parsers do
    raise ArgumentError, "Plug.Parsers expects a set of parsers to be given in :parsers"
  end

  defp convert_parsers(parsers) do
    for parser <- parsers do
      case Atom.to_string(parser) do
        "Elixir." <> _ -> parser
        reference      -> Module.concat(Plug.Parsers, String.upcase(reference))
      end
    end
  end

  def call(%Conn{req_headers: req_headers, method: method,
                 body_params: %Plug.Conn.Unfetched{}} = conn, opts) when method in @methods do
    conn = Conn.fetch_query_params(conn)
    case List.keyfind(req_headers, "content-type", 0) do
      {"content-type", ct} ->
        case Conn.Utils.content_type(ct) do
          {:ok, type, subtype, headers} ->
            reduce(conn, Keyword.fetch!(opts, :parsers), type, subtype, headers, opts)
          :error ->
            %{conn | body_params: %{}}
        end
      nil ->
        %{conn | body_params: %{}}
    end
  end

  def call(%Conn{body_params: %Plug.Conn.Unfetched{}} = conn, _opts) do
    conn = Conn.fetch_query_params(conn)
    %{conn | body_params: %{}}
  end

  def call(%Conn{} = conn, _opts) do
    Conn.fetch_query_params(conn)
  end

  defp reduce(conn, [h|t], type, subtype, headers, opts) do
    case h.parse(conn, type, subtype, headers, opts) do
      {:ok, body, %Conn{params: %Plug.Conn.Unfetched{}, query_params: query} = conn} ->
        %{conn | body_params: body, params: query |> Map.merge(body)}
      {:ok, body, %Conn{params: params, query_params: query} = conn} ->
        %{conn | body_params: body, params: params |> Map.merge(query) |> Map.merge(body)}
      {:next, conn} ->
        reduce(conn, t, type, subtype, headers, opts)
      {:error, :too_large, _conn} ->
        raise RequestTooLargeError
    end
  end

  defp reduce(conn, [], type, subtype, _headers, opts) do
    ensure_accepted_mimes(conn, type, subtype, Keyword.fetch!(opts, :pass))
  end

  defp ensure_accepted_mimes(conn, _type, _subtype, ["*/*"]), do: conn
  defp ensure_accepted_mimes(conn, type, subtype, pass) do
    if "#{type}/#{subtype}" in pass || "#{type}/*" in pass do
      %{conn | body_params: %{}}
    else
      raise UnsupportedMediaTypeError, media_type: "#{type}/#{subtype}"
    end
  end
end
