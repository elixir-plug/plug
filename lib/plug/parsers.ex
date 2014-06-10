defmodule Plug.Parsers do
  message = "the request is too large. If you are willing to process " <>
            "larger requests, please give a :limit to Plug.Parsers"

  defmodule RequestTooLargeError do
    @moduledoc """
    Error raised when the request is too large
    """

    defexception [:message]

    defimpl Plug.Exception do
      def status(_exception) do
        413
      end
    end
  end

  defmodule UnsupportedMediaTypeError do
    @moduledoc """
    Error raised when the request body cannot be parsed
    """

    defexception [:message]

    defimpl Plug.Exception do
      def status(_exception) do
        415
      end
    end
  end

  @moduledoc """
  A plug for parsing the request body

  ## Options

  * `:parsers` - a set of modules to be invoked for parsing.
                 These modules need to implement the behaviour
                 outlined in this module.

  * `:limit` - the request size limit we accept to parse.
               Defaults to 8,000,000 bytes.

  ## Examples

      plug Plug.Parsers, parsers: [:urlencoded, :multipart]

  ## Built-in parsers

  Plug ships with the following parsers:

  * `Plug.Parsers.URLENCODED` - parses "application/x-www-form-urlencoded" requests
  * `Plug.Parsers.MULTIPART` - parses "multipart/form-data" and "multipart/mixed" requests

  This plug will raise `Plug.Parsers.UnsupportedMediaTypeError` if
  the request cannot be parsed by any of the given types and raise
  `Plug.Parsers.RequestTooLargeError` if the request goes over the
  given limit.

  ## File handling

  If a file is uploaded via any of the parsers, Plug will
  stream the uploaded contents to a file in a temporary directory,
  avoiding loading the whole file into memory. For such, it is
  required that the `:plug` application is started.

  In those cases, the parameter will return a `Plug.Upload`
  struct with information about the file and its content type.

  You can customize the temporary directory by setting the `PLUG_TMPDIR`
  environment variable in your system.
  """

  alias Plug.Conn
  use Behaviour

  @doc """
  Attempt to parse the connection request body given the type,
  subtype and headers. Returns `{:ok, conn}` if the parser can
  handle the given content type, `{:halt, conn}` otherwise.
  """
  defcallback parse(Conn.t, type :: binary, subtype :: binary,
                    headers :: Keyword.t, opts :: Keyword.t) ::
                    {:ok, Conn.params, Conn.t} |
                    {:error, :too_large, Conn.t} |
                    {:skip, Conn.t}

  @behaviour Plug

  def init(opts) do
    parsers = Keyword.get(opts, :parsers) || raise_missing_parsers
    opts
    |> Keyword.put(:parsers, convert_parsers(parsers))
    |> Keyword.put_new(:limit, 8_000_000)
  end

  defp raise_missing_parsers do
    raise ArgumentError, message: "Plug.Parsers expects a set of parsers to be given in :parsers"
  end

  defp convert_parsers(parsers) do
    for parser <- parsers do
      case atom_to_binary(parser) do
        "Elixir." <> _ -> parser
        reference      -> Module.concat(Plug.Parsers, String.upcase(reference))
      end
    end
  end

  def call(%Conn{req_headers: req_headers} = conn, opts) do
    conn = Plug.Conn.fetch_params(conn)
    case List.keyfind(req_headers, "content-type", 0) do
      {"content-type", ct} ->
        case Plug.Conn.Utils.content_type(ct) do
          {:ok, type, subtype, headers} ->
            reduce(conn, Keyword.fetch!(opts, :parsers), type, subtype, headers, opts)
          :error ->
            conn
        end
      nil ->
        conn
    end
  end

  defp reduce(conn, [h|t], type, subtype, headers, opts) do
    case h.parse(conn, type, subtype, headers, opts) do
      {:ok, post, %Conn{params: get} = conn} ->
        %{conn | params: Map.merge(get, post)}
      {:next, conn} ->
        reduce(conn, t, type, subtype, headers, opts)
      {:error, :too_large, _conn} ->
        raise Plug.Parsers.RequestTooLargeError
    end
  end

  defp reduce(_conn, [], type, subtype, _headers, _opts) do
    raise UnsupportedMediaTypeError,
          message: "unsupported media type #{type}/#{subtype}"
  end
end
