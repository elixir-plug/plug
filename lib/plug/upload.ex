defmodule Plug.Upload do
  @moduledoc """
  A server (a `GenServer` specifically) that manages uploaded files.

  Uploaded files are stored in a temporary directory
  and removed from that directory after the process that
  requested the file dies.

  During the request, files are represented with
  a `Plug.Upload` struct that contains three fields:

  * `:path` - the path to the uploaded file on the filesystem
  * `:content_type` - the content type of the uploaded file
  * `:filename` - the filename of the uploaded file given in the request

  **Note**: as mentioned in the documentation for `Plug.Parsers`, the `:plug`
  application has to be started in order to upload files and use the
  `Plug.Upload` module.
  """

  defstruct [:path, :content_type, :filename]
  @type t :: %__MODULE__{
    path: Path.t,
    filename: binary,
    content_type: binary | nil
  }

  @doc """
  Requests a random file to be created in the upload directory
  with the given prefix.
  """
  @spec random_file(binary) ::
        {:ok, binary} |
        {:too_many_attempts, binary, pos_integer} |
        {:no_tmp, [binary]}
  def random_file(prefix) do
    GenServer.call(plug_server, {:random, prefix})
  end

  @doc """
  Requests a random file to be created in the upload directory
  with the given prefix. Raises on failure.
  """
  @spec random_file!(binary) :: binary | no_return
  def random_file!(prefix) do
    case random_file(prefix) do
      {:ok, path} ->
        path
      {:too_many_attempts, tmp, attempts} ->
        raise "tried #{attempts} times to create an uploaded file at #{tmp} but failed. What gives?"
      {:no_tmp, _tmps} ->
        raise "could not create a tmp directory to store uploads. Set PLUG_TMPDIR to a directory with write permission"
    end
  end

  defp plug_server do
    Process.whereis(__MODULE__) ||
      raise "could not find process Plug.Upload. Have you started the :plug application?"
  end

  use GenServer

  @doc """
  Starts the upload handling server.
  """
  def start_link() do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  ## Callbacks

  @temp_env_vars ~w(PLUG_TMPDIR TMPDIR TMP TEMP)s
  @max_attempts 10

  @doc false
  def init(:ok) do
    tmp = Enum.find_value @temp_env_vars, "/tmp", &System.get_env/1
    cwd = Path.join(File.cwd!, "tmp")
    ets = :ets.new(:plug_uploads, [:private])
    {:ok, {[tmp, cwd], ets}}
  end

  @doc false
  def handle_call({:random, prefix}, {pid, _ref}, {tmps, ets} = state) do
    case find_tmp_dir(pid, tmps, ets) do
      {:ok, tmp, paths} ->
        {:reply, open_random_file(prefix, tmp, 0, pid, ets, paths), state}
      {:no_tmp, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(msg, from, state) do
    super(msg, from, state)
  end

  @doc false
  def handle_info({:DOWN, _ref, :process, pid, _reason}, {_, ets} = state) do
    case :ets.lookup(ets, pid) do
      [{pid, _tmp, paths}] ->
        :ets.delete(ets, pid)
        Enum.each paths, &:file.delete/1
      [] ->
        :ok
    end
    {:noreply, state}
  end

  def handle_info(msg, state) do
    super(msg, state)
  end

  ## Helpers

  defp find_tmp_dir(pid, tmps, ets) do
    case :ets.lookup(ets, pid) do
      [{^pid, tmp, paths}] ->
        {:ok, tmp, paths}
      [] ->
        if tmp = ensure_tmp_dir(tmps) do
          :erlang.monitor(:process, pid)
          :ets.insert(ets, {pid, tmp, []})
          {:ok, tmp, []}
        else
          {:no_tmp, tmps}
        end
    end
  end

  defp ensure_tmp_dir(tmps) do
    {mega, _, _} = :os.timestamp
    subdir = "/plug-" <> i(mega)
    Enum.find_value(tmps, &write_tmp_dir(&1 <> subdir))
  end

  defp write_tmp_dir(path) do
    case File.mkdir_p(path) do
      :ok -> path
      {:error, _} -> nil
    end
  end

  defp open_random_file(prefix, tmp, attempts, pid, ets, paths) when attempts < @max_attempts do
    path = path(prefix, tmp)

    case :file.write_file(path, "", [:write, :raw, :exclusive, :binary]) do
      :ok ->
        :ets.update_element(ets, pid, {3, [path|paths]})
        {:ok, path}
      {:error, reason} when reason in [:eexist, :eaccess] ->
        open_random_file(prefix, tmp, attempts + 1, pid, ets, paths)
    end
  end

  defp open_random_file(_prefix, tmp, attempts, _pid, _ets, _paths) do
    {:too_many_attempts, tmp, attempts}
  end

  @compile {:inline, i: 1}

  defp i(integer), do: Integer.to_string(integer)

  defp path(prefix, tmp) do
    {_mega, sec, micro} = :os.timestamp
    scheduler_id = :erlang.system_info(:scheduler_id)
    tmp <> "/" <> prefix <> "-" <> i(sec) <> "-" <> i(micro) <> "-" <> i(scheduler_id)
  end
end
