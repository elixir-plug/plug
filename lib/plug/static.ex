defmodule Plug.Static do
  @moduledoc """
  A plug for serving static assets.

  It requires two options:

    * `:at` - the request path to reach for static assets.
      It must be a string.

    * `:from` - the file system path to read static assets from.
      It can be either: a string containing a file system path, an
      atom representing the application name (where assets will
      be served from `priv/static`), a tuple containing the
      application name and the directory to serve assets from (besides
      `priv/static`), or an MFA tuple.

  The preferred form is to use `:from` with an atom or tuple, since
  it will make your application independent from the starting directory.
  For example, if you pass:

      plug Plug.Static, from: "priv/app/path"

  Plug.Static will be unable to serve assets if you build releases
  or if you change the current directory. Instead do:

      plug Plug.Static, from: {:app_name, "priv/app/path"}

  If a static asset cannot be found, `Plug.Static` simply forwards
  the connection to the rest of the pipeline.

  ## Cache mechanisms

  `Plug.Static` uses etags for HTTP caching. This means browsers/clients
  should cache assets on the first request and validate the cache on
  following requests, not downloading the static asset once again if it
  has not changed. The cache-control for etags is specified by the
  `cache_control_for_etags` option and defaults to `"public"`.

  However, `Plug.Static` also supports direct cache control by using
  versioned query strings. If the request query string starts with
  "?vsn=", `Plug.Static` assumes the application is versioning assets
  and does not set the `ETag` header, meaning the cache behaviour will
  be specified solely by the `cache_control_for_vsn_requests` config,
  which defaults to `"public, max-age=31536000"`.

  ## Options

    * `:gzip` - given a request for `FILE`, serves `FILE.gz` if it exists
      in the static directory and if the `accept-encoding` header is set
      to allow gzipped content (defaults to `false`).

    * `:brotli` - given a request for `FILE`, serves `FILE.br` if it exists
      in the static directory and if the `accept-encoding` header is set
      to allow brotli-compressed content (defaults to `false`).
      `FILE.br` is checked first and dominates `FILE.gz` due to the better
      compression ratio.

    * `:cache_control_for_etags` - sets the cache header for requests
      that use etags. Defaults to `"public"`.

    * `:etag_generation` - specify a `{module, function, args}` to be used
      to generate   an etag. The `path` of the resource will be passed to
      the function, as well as the `args`. If this option is not supplied,
      etags will be generated based off of file size and modification time.
      Note it is [recommended for the etag value to be quoted](https://tools.ietf.org/html/rfc7232#section-2.3),
      which Plug won't do automatically.

    * `:cache_control_for_vsn_requests` - sets the cache header for
      requests starting with "?vsn=" in the query string. Defaults to
      `"public, max-age=31536000"`.

    * `:only` - filters which requests to serve. This is useful to avoid
      file system access on every request when this plug is mounted
      at `"/"`. For example, if `only: ["images", "favicon.ico"]` is
      specified, only files in the "images" directory and the
      "favicon.ico" file will be served by `Plug.Static`.
      Note that `Plug.Static` matches these filters against request
      uri and not against the filesystem. When requesting
      a file with name containing non-ascii or special characters,
      you should use urlencoded form. For example, you should write
      `only: ["file%20name"]` instead of `only: ["file name"]`.
      Defaults to `nil` (no filtering).

    * `:only_matching` - a relaxed version of `:only` that will
      serve any request as long as one of the given values matches the
      given path. For example, `only_matching: ["images", "favicon"]`
      will match any request that starts at "images" or "favicon",
      be it "/images/foo.png", "/images-high/foo.png", "/favicon.ico"
      or "/favicon-high.ico". Such matches are useful when serving
      digested files at the root. Defaults to `nil` (no filtering).

    * `:headers` - other headers to be set when serving static assets. Specify either
      an enum of key-value pairs or a `{module, function, args}` to return an enum. The
      `conn` will be passed to the function, as well as the `args`.

    * `:content_types` - custom MIME type mapping. As a map with filename as key
      and content type as value. For example:
      `content_types: %{"apple-app-site-association" => "application/json"}`.

  ## Examples

  This plug can be mounted in a `Plug.Builder` pipeline as follows:

      defmodule MyPlug do
        use Plug.Builder

        plug Plug.Static,
          at: "/public",
          from: :my_app,
          only: ~w(images robots.txt)
        plug :not_found

        def not_found(conn, _) do
          send_resp(conn, 404, "not found")
        end
      end

  """

  @behaviour Plug
  @allowed_methods ~w(GET HEAD)

  import Plug.Conn
  alias Plug.Conn

  # In this module, the `:prim_file` Erlang module along with the `:file_info`
  # record are used instead of the more common and Elixir-y `File` module and
  # `File.Stat` struct, respectively. The reason behind this is performance: all
  # the `File` operations pass through a single process in order to support node
  # operations that we simply don't need when serving assets.

  require Record
  Record.defrecordp(:file_info, Record.extract(:file_info, from_lib: "kernel/include/file.hrl"))

  defmodule InvalidPathError do
    defexception message: "invalid path for static asset", plug_status: 400
  end

  @impl true
  def init(opts) do
    from =
      case Keyword.fetch!(opts, :from) do
        {_, _} = from -> from
        {_, _, _} = from -> from
        from when is_atom(from) -> {from, "priv/static"}
        from when is_binary(from) -> from
        _ -> raise ArgumentError, ":from must be an atom, a binary or a tuple"
      end

    %{
      gzip?: Keyword.get(opts, :gzip, false),
      brotli?: Keyword.get(opts, :brotli, false),
      only_rules: {Keyword.get(opts, :only, []), Keyword.get(opts, :only_matching, [])},
      qs_cache: Keyword.get(opts, :cache_control_for_vsn_requests, "public, max-age=31536000"),
      et_cache: Keyword.get(opts, :cache_control_for_etags, "public"),
      et_generation: Keyword.get(opts, :etag_generation, nil),
      headers: Keyword.get(opts, :headers, %{}),
      content_types: Keyword.get(opts, :content_types, %{}),
      from: from,
      at: opts |> Keyword.fetch!(:at) |> Plug.Router.Utils.split()
    }
  end

  @impl true
  def call(
        conn = %Conn{method: meth},
        %{at: at, only_rules: only_rules, from: from, gzip?: gzip?, brotli?: brotli?} = options
      )
      when meth in @allowed_methods do
    segments = subset(at, conn.path_info)

    if allowed?(only_rules, segments) do
      segments = Enum.map(segments, &uri_decode/1)

      if invalid_path?(segments) do
        raise InvalidPathError
      end

      path = path(from, segments)
      range = get_req_header(conn, "range")
      encoding = file_encoding(conn, path, range, gzip?, brotli?)
      serve_static(encoding, conn, segments, range, options)
    else
      conn
    end
  end

  def call(conn, _options) do
    conn
  end

  defp uri_decode(path) do
    # TODO: Remove rescue as this can't fail from Elixir v1.13
    try do
      URI.decode(path)
    rescue
      ArgumentError ->
        raise InvalidPathError
    end
  end

  defp allowed?(_only_rules, []), do: false
  defp allowed?({[], []}, _list), do: true

  defp allowed?({full, prefix}, [h | _]) do
    h in full or (prefix != [] and match?({0, _}, :binary.match(h, prefix)))
  end

  defp serve_static({content_encoding, file_info, path}, conn, segments, range, options) do
    %{
      qs_cache: qs_cache,
      et_cache: et_cache,
      et_generation: et_generation,
      headers: headers,
      content_types: types
    } = options

    case put_cache_header(conn, qs_cache, et_cache, et_generation, file_info, path) do
      {:stale, conn} ->
        filename = List.last(segments)
        content_type = Map.get(types, filename) || MIME.from_path(filename)

        conn
        |> put_resp_header("content-type", content_type)
        |> put_resp_header("accept-ranges", "bytes")
        |> maybe_add_encoding(content_encoding)
        |> merge_headers(headers)
        |> serve_range(file_info, path, range, options)

      {:fresh, conn} ->
        conn
        |> maybe_add_vary(options)
        |> send_resp(304, "")
        |> halt()
    end
  end

  defp serve_static(:error, conn, _segments, _range, _options) do
    conn
  end

  defp serve_range(conn, file_info, path, [range], options) do
    file_info(size: file_size) = file_info

    with %{"bytes" => bytes} <- Plug.Conn.Utils.params(range),
         {range_start, range_end} <- start_and_end(bytes, file_size) do
      send_range(conn, path, range_start, range_end, file_size, options)
    else
      _ -> send_entire_file(conn, path, options)
    end
  end

  defp serve_range(conn, _file_info, path, _range, options) do
    send_entire_file(conn, path, options)
  end

  defp start_and_end("-" <> rest, file_size) do
    case Integer.parse(rest) do
      {last, ""} when last > 0 and last <= file_size -> {file_size - last, file_size - 1}
      _ -> :error
    end
  end

  defp start_and_end(range, file_size) do
    case Integer.parse(range) do
      {first, "-"} when first >= 0 ->
        {first, file_size - 1}

      {first, "-" <> rest} when first >= 0 ->
        case Integer.parse(rest) do
          {last, ""} when last >= first -> {first, min(last, file_size - 1)}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp send_range(conn, path, 0, range_end, file_size, options) when range_end == file_size - 1 do
    send_entire_file(conn, path, options)
  end

  defp send_range(conn, path, range_start, range_end, file_size, _options) do
    length = range_end - range_start + 1

    conn
    |> put_resp_header("content-range", "bytes #{range_start}-#{range_end}/#{file_size}")
    |> send_file(206, path, range_start, length)
    |> halt()
  end

  defp send_entire_file(conn, path, options) do
    conn
    |> maybe_add_vary(options)
    |> send_file(200, path)
    |> halt()
  end

  defp maybe_add_encoding(conn, nil), do: conn
  defp maybe_add_encoding(conn, ce), do: put_resp_header(conn, "content-encoding", ce)

  defp maybe_add_vary(conn, %{gzip?: gzip?, brotli?: brotli?}) do
    # If we serve gzip or brotli at any moment, we need to set the proper vary
    # header regardless of whether we are serving gzip content right now.
    # See: http://www.fastly.com/blog/best-practices-for-using-the-vary-header/
    if gzip? or brotli? do
      update_in(conn.resp_headers, &[{"vary", "Accept-Encoding"} | &1])
    else
      conn
    end
  end

  defp put_cache_header(
         %Conn{query_string: "vsn=" <> _} = conn,
         qs_cache,
         _et_cache,
         _et_generation,
         _file_info,
         _path
       )
       when is_binary(qs_cache) do
    {:stale, put_resp_header(conn, "cache-control", qs_cache)}
  end

  defp put_cache_header(conn, _qs_cache, et_cache, et_generation, file_info, path)
       when is_binary(et_cache) do
    etag = etag_for_path(file_info, et_generation, path)

    conn =
      conn
      |> put_resp_header("cache-control", et_cache)
      |> put_resp_header("etag", etag)

    if etag in get_req_header(conn, "if-none-match") do
      {:fresh, conn}
    else
      {:stale, conn}
    end
  end

  defp put_cache_header(conn, _, _, _, _, _) do
    {:stale, conn}
  end

  defp etag_for_path(file_info, et_generation, path) do
    case et_generation do
      {module, function, args} ->
        apply(module, function, [path | args])

      nil ->
        file_info(size: size, mtime: mtime) = file_info
        <<?", {size, mtime} |> :erlang.phash2() |> Integer.to_string(16)::binary, ?">>
    end
  end

  defp file_encoding(conn, path, [_range], _gzip?, _brotli?) do
    # We do not support compression for range queries.
    file_encoding(conn, path, nil, false, false)
  end

  defp file_encoding(conn, path, _range, gzip?, brotli?) do
    cond do
      file_info = brotli? and accept_encoding?(conn, "br") && regular_file_info(path <> ".br") ->
        {"br", file_info, path <> ".br"}

      file_info = gzip? and accept_encoding?(conn, "gzip") && regular_file_info(path <> ".gz") ->
        {"gzip", file_info, path <> ".gz"}

      file_info = regular_file_info(path) ->
        {nil, file_info, path}

      true ->
        :error
    end
  end

  defp regular_file_info(path) do
    case :prim_file.read_file_info(path) do
      {:ok, file_info(type: :regular) = file_info} ->
        file_info

      _ ->
        nil
    end
  end

  defp accept_encoding?(conn, encoding) do
    encoding? = &String.contains?(&1, [encoding, "*"])

    Enum.any?(get_req_header(conn, "accept-encoding"), fn accept ->
      accept |> Plug.Conn.Utils.list() |> Enum.any?(encoding?)
    end)
  end

  defp path({module, function, arguments}, segments)
       when is_atom(module) and is_atom(function) and is_list(arguments),
       do: Enum.join([apply(module, function, arguments) | segments], "/")

  defp path({app, from}, segments) when is_atom(app) and is_binary(from),
    do: Enum.join([Application.app_dir(app), from | segments], "/")

  defp path(from, segments),
    do: Enum.join([from | segments], "/")

  defp subset([h | expected], [h | actual]), do: subset(expected, actual)
  defp subset([], actual), do: actual
  defp subset(_, _), do: []

  defp invalid_path?(list) do
    invalid_path?(list, :binary.compile_pattern(["/", "\\", ":", "\0"]))
  end

  defp invalid_path?([h | _], _match) when h in [".", "..", ""], do: true
  defp invalid_path?([h | t], match), do: String.contains?(h, match) or invalid_path?(t)
  defp invalid_path?([], _match), do: false

  defp merge_headers(conn, {module, function, args}) do
    merge_headers(conn, apply(module, function, [conn | args]))
  end

  defp merge_headers(conn, headers) do
    merge_resp_headers(conn, headers)
  end
end
