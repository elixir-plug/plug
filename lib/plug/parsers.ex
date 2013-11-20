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

  ## Built-in parsers

  Plug ships with the following parsers:

  * `Plug.Parsers.URLENCODED`
  * `Plug.Parsers.MULTIPART`

  """

  alias Plug.Conn
  use Behaviour

  @doc """
  Attempt to parse the connection request body given the type,
  subtype and headers. Returns `{ :ok, conn }` if the parser can
  handle the given content type, `{ :halt, conn }` otherwise.
  """
  defcallback parse(Conn.t, type :: binary, subtype :: binary,
                    headers :: Keyword.t, opts :: Keyword.t) :: { :ok | :halt, Conn.t }

  # TODO: Add upload manager
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
      { :halt, conn } ->
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
