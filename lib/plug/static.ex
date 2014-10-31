defmodule Plug.Static do
  @moduledoc """
  A plug for serving static assets.

  It expects two options on initialization:

    * `:at` - the request path to reach for static assets.
      It must be a binary.

    * `:from` - the filesystem path to read static assets from.
      It must be a binary, containing a file system path, or an
      atom representing the application name, where assets will
      be served from the priv/static.

  The preferred form is to use `:from` with an atom, since
  it will make your application independent from the starting
  directory.

  If a static asset cannot be found, it simply forwards
  the connection to the rest of the pipeline.

  ## Options

    * `:gzip` - use `FILE.gz` if it exists in the static directory
      and if `accept-encoding` is set to allow gzipped content
      (defaults to `false`).

    * `:cache` - sets cache headers on response (defaults to: `true`)

  ## Examples

  This filter can be mounted in a Plug.Builder as follow:

      defmodule MyPlug do
        use Plug.Builder

        plug Plug.Static, at: "/public", from: :my_app
        plug :not_found

        def not_found(conn, _) do
          Plug.Conn.send_resp(conn, 404, "not found")
        end
      end

  """

  @behaviour Plug
  @allowed_methods ~w(GET HEAD)

  import Plug.Conn
  alias Plug.Conn

  defmodule InvalidPathError do
    defexception message: "invalid path for static asset", plug_status: 400
  end

  def init(opts) do
    at    = Keyword.fetch!(opts, :at)
    from  = Keyword.fetch!(opts, :from)
    gzip  = Keyword.get(opts, :gzip, false)
    cache = Keyword.get(opts, :cache, true)

    unless is_atom(from) or is_binary(from) do
      raise ArgumentError, message: ":from must be an atom or a binary"
    end

    {Plug.Router.Utils.split(at), from, gzip, cache}
  end

  def call(conn = %Conn{method: meth}, {at, from, gzip, cache}) when meth in @allowed_methods do
    send_static_file(conn, at, from, gzip, cache)
  end
  def call(conn, _opts), do: conn

  defp send_static_file(conn, at, from, gzip, cache) do
    segments = subset(at, conn.path_info)
    segments = for segment <- List.wrap(segments), do: URI.decode(segment)
    path     = path(from, segments)

    cond do
      segments in [nil, []] ->
        conn
      invalid_path?(segments) ->
        raise InvalidPathError
      true ->
        case file_encoding(conn, path, gzip) do
          {conn, path} ->
            if cache do
              conn = put_resp_header(conn, "cache-control", "public, max-age=31536000")
            end

            conn
            |> put_resp_header("content-type", Plug.MIME.path(List.last(segments)))
            |> send_file(200, path)
            |> halt
          :error ->
            conn
        end
    end
  end

  defp file_encoding(conn, path, gzip) do
    path_gz = path <> ".gz"

    cond do
      gzip && gzip?(conn) && File.regular?(path_gz) ->
        {put_resp_header(conn, "content-encoding", "gzip"), path_gz}
      File.regular?(path) ->
        {conn, path}
      true ->
        :error
    end
  end

  defp gzip?(conn) do
    fun = &(:binary.match(&1, ["gzip", "*"]) != :nomatch)
    Enum.any? get_req_header(conn, "accept-encoding"), fn accept ->
      Enum.any?(Plug.Conn.Utils.list(accept), fun)
    end
  end

  defp path(from, segments) when is_atom(from),
    do: Path.join([Application.app_dir(from), "priv/static" | segments])

  defp path(from, segments),
    do: Path.join([from | segments])

  defp subset([h|expected], [h|actual]),
    do: subset(expected, actual)
  defp subset([], actual),
    do: actual
  defp subset(_, _), do:
    nil

  defp invalid_path?([h|_]) when h in [".", "..", ""], do: true
  defp invalid_path?([h|t]) do
    case :binary.match(h, ["/", "\\", ":"]) do
      {_, _} -> true
      :nomatch -> invalid_path?(t)
    end
  end
  defp invalid_path?([]), do: false
end
