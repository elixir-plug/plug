defmodule Plug.Upload.Supervisor do
  @moduledoc false
  use Supervisor

  @temp_env_vars ~w(PLUG_TMPDIR TMPDIR TMP TEMP)s
  @dir_table Plug.Upload.Dir
  @path_table Plug.Upload.Path
  @otp_vsn System.otp_release() |> String.to_integer()
  @write_mode if @otp_vsn >= 25, do: :auto, else: true
  @ets_opts [:public, :named_table, read_concurrency: true, write_concurrency: @write_mode]

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    # Initialize the upload system
    tmp = Enum.find_value(@temp_env_vars, "/tmp", &System.get_env/1) |> Path.expand()
    cwd = Path.join(File.cwd!(), "tmp")
    # Add a tiny random component to avoid clashes between nodes
    suffix = :crypto.strong_rand_bytes(3) |> Base.url_encode64()
    :persistent_term.put(Plug.Upload, {[tmp, cwd], suffix})
    :ets.new(@dir_table, [:set | @ets_opts])
    :ets.new(@path_table, [:duplicate_bag | @ets_opts])

    children = [
      Plug.Upload.Terminator,
      {PartitionSupervisor, child_spec: Plug.Upload, name: Plug.Upload}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
