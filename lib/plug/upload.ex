defmodule Plug.UploadError do
  defexception [:message]
end

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

  ## Security

  The `:content_type` and `:filename` fields in the `Plug.Upload` struct are
  client-controlled. These values should be validated, via file content
  inspection or similar, before being trusted.
  """

  use GenServer
  defstruct [:path, :content_type, :filename]

  @type t :: %__MODULE__{
          path: Path.t(),
          filename: binary,
          content_type: binary | nil
        }

  @dir_table __MODULE__.Dir
  @path_table __MODULE__.Path
  @max_attempts 10
  @temp_env_vars ~w(PLUG_TMPDIR TMPDIR TMP TEMP)s

  @doc """
  Requests a random file to be created in the upload directory
  with the given prefix.
  """
  @spec random_file(binary) ::
          {:ok, binary}
          | {:too_many_attempts, binary, pos_integer}
          | {:no_tmp, [binary]}
  def random_file(prefix) do
    case ensure_tmp() do
      {:ok, tmp} ->
        open_random_file(prefix, tmp, 0)

      {:no_tmp, tmps} ->
        {:no_tmp, tmps}
    end
  end

  @doc """
  Assign ownership of the given upload file to another process.

  Useful if you want to do some work on an uploaded file in another process
  since it means that the file will survive the end of the request.
  """
  @spec give_away(t | binary, pid, pid) :: :ok | {:error, :unknown_path}
  def give_away(upload, to_pid, from_pid \\ self())

  def give_away(%__MODULE__{path: path}, to_pid, from_pid) do
    give_away(path, to_pid, from_pid)
  end

  def give_away(path, to_pid, from_pid)
      when is_binary(path) and is_pid(to_pid) and is_pid(from_pid) do
    with [{^from_pid, _tmp}] <- :ets.lookup(@dir_table, from_pid),
         true <- path_owner?(from_pid, path) do
      case :ets.lookup(@dir_table, to_pid) do
        [{^to_pid, _tmp}] ->
          :ets.insert(@path_table, {to_pid, path})
          :ets.delete_object(@path_table, {from_pid, path})

          :ok

        [] ->
          server = plug_server()
          {:ok, tmp} = generate_tmp_dir()
          :ok = GenServer.call(server, {:give_away, to_pid, tmp, path})
          :ets.delete_object(@path_table, {from_pid, path})
          :ok
      end
    else
      _ ->
        {:error, :unknown_path}
    end
  end

  defp ensure_tmp() do
    pid = self()

    case :ets.lookup(@dir_table, pid) do
      [{^pid, tmp}] ->
        {:ok, tmp}

      [] ->
        server = plug_server()
        GenServer.cast(server, {:monitor, pid})

        with {:ok, tmp} <- generate_tmp_dir() do
          true = :ets.insert_new(@dir_table, {pid, tmp})
          {:ok, tmp}
        end
    end
  end

  defp generate_tmp_dir() do
    tmp_roots = :persistent_term.get(__MODULE__)
    {mega, _, _} = :os.timestamp()
    subdir = "/plug-" <> i(mega)

    if tmp = Enum.find_value(tmp_roots, &make_tmp_dir(&1 <> subdir)) do
      {:ok, tmp}
    else
      {:no_tmp, tmp_roots}
    end
  end

  defp make_tmp_dir(path) do
    case File.mkdir_p(path) do
      :ok -> path
      {:error, _} -> nil
    end
  end

  defp open_random_file(prefix, tmp, attempts) when attempts < @max_attempts do
    path = path(prefix, tmp)

    case :file.write_file(path, "", [:write, :raw, :exclusive, :binary]) do
      :ok ->
        :ets.insert(@path_table, {self(), path})
        {:ok, path}

      {:error, reason} when reason in [:eexist, :eacces] ->
        open_random_file(prefix, tmp, attempts + 1)
    end
  end

  defp open_random_file(_prefix, tmp, attempts) do
    {:too_many_attempts, tmp, attempts}
  end

  defp path(prefix, tmp) do
    sec = :os.system_time(:second)
    rand = :rand.uniform(999_999_999_999)
    scheduler_id = :erlang.system_info(:scheduler_id)
    tmp <> "/" <> prefix <> "-" <> i(sec) <> "-" <> i(rand) <> "-" <> i(scheduler_id)
  end

  defp path_owner?(pid, path) do
    owned_paths = :ets.lookup(@path_table, pid)
    Enum.any?(owned_paths, fn {_pid, p} -> p == path end)
  end

  @compile {:inline, i: 1}
  defp i(integer), do: Integer.to_string(integer)

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
        raise Plug.UploadError,
              "tried #{attempts} times to create an uploaded file at #{tmp} but failed. " <>
                "Set PLUG_TMPDIR to a directory with write permission"

      {:no_tmp, _tmps} ->
        raise Plug.UploadError,
              "could not create a tmp directory to store uploads. " <>
                "Set PLUG_TMPDIR to a directory with write permission"
    end
  end

  defp plug_server do
    Process.whereis(__MODULE__) ||
      raise Plug.UploadError,
            "could not find process Plug.Upload. Have you started the :plug application?"
  end

  @doc false
  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  ## Callbacks

  @impl true
  def init(:ok) do
    Process.flag(:trap_exit, true)
    tmp = Enum.find_value(@temp_env_vars, "/tmp", &System.get_env/1) |> Path.expand()
    cwd = Path.join(File.cwd!(), "tmp")
    :persistent_term.put(__MODULE__, [tmp, cwd])

    :ets.new(@dir_table, [:named_table, :public, :set])
    :ets.new(@path_table, [:named_table, :public, :duplicate_bag])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:give_away, pid, tmp, path}, _from, state) do
    # Since we are writing in behalf of another process, we need to make sure
    # the monitor and writing to the tables happen within the same operation.
    Process.monitor(pid)
    :ets.insert_new(@dir_table, {pid, tmp})
    :ets.insert(@path_table, {pid, path})

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:monitor, pid}, state) do
    Process.monitor(pid)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    case :ets.lookup(@dir_table, pid) do
      [{pid, _tmp}] ->
        :ets.delete(@dir_table, pid)

        @path_table
        |> :ets.lookup(pid)
        |> Enum.each(&delete_path/1)

        :ets.delete(@path_table, pid)

      [] ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    folder = fn entry, :ok -> delete_path(entry) end
    :ets.foldl(folder, :ok, @path_table)
  end

  defp delete_path({_pid, path}) do
    :file.delete(path)
    :ok
  end
end
