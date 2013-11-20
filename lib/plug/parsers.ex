defmodule Plug.Parsers do
  message = "the request is too large. If you are willing to process " <>
            "larger requests, please give a :limit to Plug.Parsers"

  defexception RequestTooLargeError, conn: nil, message: message do
    defimpl Plug.Exception do
      def status(_exception) do
        413
      end
    end
  end

  defexception UnsupportedMediaTypeError, [:message, :conn] do
    defimpl Plug.Exception do
      def status(_exception) do
        415
      end
    end
  end

  @moduledoc """
  A plug responsible for parsing the request body.

  ## Options

  * `:parsers` - a set of modules to be invoked for parsing.
                 Those modules need to implement the behaviour
                 outlined in this module.

  * `:limit` - the request size limit we accept to parse.
               Defaults to 8_000_000 bytes.

  ## Examples

      Plug.Parsers.call(conn, parsers:
                        [Plug.Parsers.URLENCODED, Plug.Parsers.MULTIPART])

  ## Built-in parsers

  Plug ships with the following parsers:

  * `Plug.Parsers.URLENCODED` - parses "application/x-www-form-urlencoded" requests
  * `Plug.Parsers.MULTIPART` - parses "multipart/form-data" and "multipart/mixed" requests

  This plug will raise `Plug.Parsers.UnsupportedMediaTypeError` if
  the request cannot be parsed by any of the given types and raise
  `Plug.Parsers.RequestTooLargeError` if the request goes over the
  given limit.

  ## File handling

  In case a file is uploaded via any of the parsers, Plug will
  stream the uploaded contents to a file in a temporary directory,
  avoiding loading the whole file into memory. For such, it is
  required that the `:plug` application is started.

  In those cases, the parameter will return a `Plug.Upload.File[]`
  record with information about the file and its content type.

  You can customize the temporary directory by setting the `PLUG_TMPDIR`
  environment variable in your system.
  """

  alias Plug.Conn
  use Behaviour

  @doc """
  Attempt to parse the connection request body given the type,
  subtype and headers. Returns `{ :ok, conn }` if the parser can
  handle the given content type, `{ :halt, conn }` otherwise.
  """
  defcallback parse(Conn.t, type :: binary, subtype :: binary,
                    headers :: Keyword.t, opts :: Keyword.t) ::
                    { :ok, Conn.params, Conn.t } |
                    { :too_large, Conn.t } |
                    { :skip, Conn.t }

  def call(Conn[req_headers: req_headers] = conn, opts) do
    conn = Plug.Connection.fetch_params(conn)
    case List.keyfind(req_headers, "content-type", 0) do
      { "content-type", ct } ->
        case Plug.Connection.Utils.content_type(ct) do
          { :ok, type, subtype, headers } ->
            parsers = Keyword.get(opts, :parsers) || raise_missing_parsers
            opts    = Keyword.put_new(opts, :limit, 8_000_000)
            reduce(conn, parsers, type, subtype, headers, opts)
          :error ->
            { :ok, conn }
        end
      nil ->
        { :ok, conn }
    end
  end

  defp reduce(conn, [h|t], type, subtype, headers, opts) do
    case h.parse(conn, type, subtype, headers, opts) do
      { :ok, post, Conn[params: get] = conn } ->
        { :ok, conn.params(merge_params(get, post)) }
      { :next, conn } ->
        reduce(conn, t, type, subtype, headers, opts)
      { :too_large, conn } ->
        raise Plug.Parsers.RequestTooLargeError, conn: conn
    end
  end

  defp reduce(conn, [], type, subtype, _headers, _opts) do
    raise UnsupportedMediaTypeError, conn: conn,
          message: "unsupported media type #{type}/#{subtype}"
  end

  defp merge_params([], post), do: post
  defp merge_params([{ k, _ }=h|t], post) do
    case :lists.keyfind(k, 1, post) do
      { _, _ } -> merge_params(t, post)
      false -> merge_params(t, [h|post])
    end
  end

  defp raise_missing_parsers do
    raise ArgumentError, message: "Plug.Parsers expects a set of parsets to be given in :parsers"
  end
end
