defmodule Plug.Static do
  @moduledoc """
  A plug for serving static assets.

  It expects two options on initialization:

  * `:at` - the request path to reach for static assets.
            It must be a binary.

  * `:from` - the filesystem path to read static assets from.
              It must be a binary, containing a file system path,
              or an atom representing the application name,
              where assets will be served from the priv/static.

  The preferred form is to use `:from` with an atom, since
  it will make your application independent from the starting
  directory.

  If a static asset cannot be found, it simply forwards
  the connection to the rest of the stack.

  ## Examples

  This filter can be mounted in a Plug.Builder as follow:

      defmodule MyPlug do
        use Plug.Builder

        plug Plug.Static, at: "/public", from: my_app
        plug :not_found

        def not_found(conn, _) do
          Plug.Connection.send(conn, 404, "not found")
        end
      end

  """

  @behaviour Plug.Wrapper
  @allowed_methods ~w(GET HEAD)

  import Plug.Connection

  def init(opts) do
    at   = Keyword.fetch!(opts, :at)
    from = Keyword.fetch!(opts, :from)

    unless is_atom(from) or is_binary(from) do
      raise ArgumentError, message: ":from must be an atom or a binary"
    end

    { Plug.Router.Utils.split(at), from }
  end

  def wrap(conn, { at, from }, fun) do
    segments = subset(at, conn.path_info)
    segments = lc segment inlist List.wrap(segments), do: URI.decode(segment)

    cond do
      segments in [nil, []] ->
        fun.(conn)
      not conn.method in @allowed_methods ->
        send_resp(conn, 406, "Method not allowed")
      invalid_path?(segments) ->
        send_resp(conn, 400, "Bad request")
      true ->
        path = path(from, segments)
        if File.regular?(path) do
          conn
          |> put_resp_header("content-type", MIME.Types.path(List.last(segments)))
          |> put_resp_header("cache-control", "public, max-age=31536000")
          |> send_file(200, path)
        else
          fun.(conn)
        end
    end
  end

  defp path(from, segments) when is_atom(from),
    do: Path.join([:code.priv_dir(from), "static" | segments])

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
      { _, _ } -> true
      :nomatch -> invalid_path?(t)
    end
  end
  defp invalid_path?([]), do: false
end