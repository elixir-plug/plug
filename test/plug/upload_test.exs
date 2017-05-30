defmodule Plug.UploadTest do
  use ExUnit.Case, async: true

  defp spawn_lots_of_temporary_files(_stop_time, 0), do: :ok
  defp spawn_lots_of_temporary_files(stop_time, reps) do
    if :os.system_time(:milli_seconds) < stop_time do
      {pid, ref} = spawn_monitor fn ->
        {:ok, _} = Plug.Upload.random_file("sample")
      end
      spawn_lots_of_temporary_files(stop_time, reps - 1)

      :ok =
      receive do
        {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
      after
	20_000 -> :timed_out
      end
    end
  end

  test "can create lots of temporary files in a short period of time" do
    # this is necessary for windoes which does not give us microsecond resolution
    # do it in spawned processes to take advantage of auto-cleanup
    # loop for at least 50 milli seconds, or 100000 iterations
    spawn_lots_of_temporary_files(:os.system_time(:milli_seconds) + 50, 100000)
  end

  test "removes the random file on process death" do
    parent = self()

    {pid, ref} = spawn_monitor fn ->
      {:ok, path} = Plug.Upload.random_file("sample")
      send parent, {:path, path}
      File.open!(path)
    end

    path =
      receive do
        {:path, path} -> path
      after
        1_000 -> flunk "didn't get a path"
      end

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        {:ok, _} = Plug.Upload.random_file("sample")
        refute File.exists?(path)
    end
  end
end
