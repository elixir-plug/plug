defmodule Plug.TempHack do
  @moduledoc false

  @doc """
  Create a temporary directory usually
  used to store uploaded files.
  """
  def tmp_dir do
    { mega, _, _ } = :erlang.now
    dir = "plug-#{mega}"

    write_env_tmp_dir('TMPDIR', dir) ||
      write_env_tmp_dir('TMP', dir)  ||
      write_env_tmp_dir('TEMP', dir) ||
      write_tmp_dir("/tmp/" <> dir)  ||
      write_tmp_dir(Path.expand(dir)) ||
      raise "cannot create temporary directory"
  end

  defp write_env_tmp_dir(env, dir) do
    case :os.getenv(env) do
      false -> nil
      tmp   -> write_tmp_dir Path.join(tmp, dir)
    end
  end

  defp write_tmp_dir(dir) do
    case File.mkdir_p(dir) do
      :ok -> dir
      { :error, _ } -> nil
    end
  end

  @doc """
  Creates a file with random name at the given temporary
  directory. It returns the name of the file and the result
  of the executed callback as a tuple.

  In case the file could not be created after 10 attemps,
  it raises an exception.
  """
  @max_attempts 10

  def random_file(prefix) do
    random_file(prefix, tmp_dir(), 0)
  end

  defp random_file(prefix, tmp_dir, attempts) when attempts < @max_attempts do
    { mega, sec, mili } = :erlang.now()
    path = Path.join(tmp_dir, "#{prefix}-#{mega}-#{sec}-#{mili}")
    case :file.open(path, [:write, :exclusive, :binary]) do
      { :error, :eaccess } -> random_file(prefix, tmp_dir, attempts + 1)
      { :ok, file } -> { :ok, file, path }
    end
  end

  defp random_file(_, tmp_dir, attempts) do
    raise "Could not create random file at #{tmp_dir} after #{attempts} attempts. What gives?"
  end
end

defmodule Plug.Parsers.MULTIPART do
  @moduledoc false
  alias Plug.Conn

  def parse(Conn[] = conn, "multipart", subtype, _headers, opts) when subtype in ["form-data", "mixed"] do
    { adapter, state } = conn.adapter
    limit = Keyword.fetch!(opts, :limit)

    case adapter.parse_req_multipart(state, limit, &handle_headers/1) do
      { :ok, params, state } ->
        { :ok, params, conn.adapter({ adapter, state }) }
      { :too_large, state } ->
        { :too_large, conn.adapter({ adapter, state }) }
    end
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    { :halt, conn }
  end

  defp handle_headers(headers) do
    case List.keyfind(headers, "content-disposition", 0) do
      { _, disposition } -> handle_disposition(disposition, headers)
      nil -> :skip
    end
  end

  defp handle_disposition(disposition, headers) do
    case :binary.split(disposition, ";") do
      [_, params] ->
        params = Plug.Connection.Utils.params(params)
        if name = params["name"] do
          handle_disposition_params(name, params, headers)
        else
          :skip
        end
      [_] ->
        :skip
    end
  end

  defp handle_disposition_params(name, params, headers) do
    if filename = params["filename"] do
      { :ok, file, path } = Plug.TempHack.random_file("multipart")
      { :file, name, file, Plug.Upload.File[filename: filename, path: path,
                                            content_type: headers["content-type"]] }
    else
      { :binary, name }
    end
  end
end
