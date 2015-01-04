defmodule Plug.Static do
  @moduledoc """
  A plug for serving static assets.

  It requires two options on initialization:

    * `:at` - the request path to reach for static assets.
      It must be a string.

    * `:from` - the filesystem path to read static assets from.
      It must be a string, containing a file system path, or an
      atom representing the application name, where assets will
      be served from the priv/static.

  The preferred form is to use `:from` with an atom, since
  it will make your application independent from the starting
  directory.

  If a static asset cannot be found, `Plug.Static` simply forwards
  the connection to the rest of the pipeline.

  ## Options

    * `:gzip` - given a request for `FILE`, serves `FILE.gz` if it exists in the
      static directory and if the `accept-encoding` ehader is set to allow
      gzipped content (defaults to `false`).

    * `:cache_control_for_query_strings` - sets cache headers on response
      (defaults to `true`). If there is no query string, only the `etag` header
      is set; if there's a query string, the `cache-control` header is set.

  ## Examples

  This plug can be mounted in a `Plug.Builder` pipeline as follow:

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
    cache = Keyword.get(opts, :cache_control_for_query_strings, true)

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
    # subset/2 returns the segments in `conn.path_info` without the segments at
    # the beginning that are shared with `at`.
    segments = subset(at, conn.path_info) |> Enum.map(&URI.decode/1)
    path     = path(from, segments)

    if invalid_path?(segments) do
      raise InvalidPathError
    end

    case file_encoding(conn, path, gzip) do
      {conn, path} ->
        if cache, do: conn = set_cache_header(conn, path)

        content_type = segments |> List.last |> Plug.MIME.path

        conn
        |> put_resp_header("content-type", content_type)
        |> send_file(200, path)
        |> halt
      :error ->
        conn
    end
  end

  defp set_cache_header(%Conn{query_string: ""} = conn, path),
    do: conn |> put_resp_header("etag", etag_string_for_path(path))
  defp set_cache_header(conn, _path),
    do: conn |> put_resp_header("cache-control", "public, max-age=31536000")

  defp etag_string_for_path(path) do
    %File.Stat{size: size, mtime: mtime} = File.stat!(path)
    {size, mtime} |> :erlang.phash2() |> Integer.to_string(16)
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
    gzip_header? = &String.contains?(&1, ["gzip", "*"])
    Enum.any? get_req_header(conn, "accept-encoding"), fn accept ->
      accept |> Plug.Conn.Utils.list() |> Enum.any?(gzip_header?)
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
  defp subset(_, _),
    do: []

  defp invalid_path?([h|_]) when h in [".", "..", ""], do: true
  defp invalid_path?([h|t]) do
    if String.contains?(h, ["/", "\\", ":"]), do: true, else: invalid_path?(t)
  end
  defp invalid_path?([]), do: false
end
