defmodule Plug.UploadTest do
  use ExUnit.Case, async: true

  test "removes the random file on process death" do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        {:ok, path} = Plug.Upload.random_file("sample")
        send(parent, {:path, path})
        File.open!(path)
      end)

    path =
      receive do
        {:path, path} -> path
      after
        1_000 -> flunk("didn't get a path")
      end

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        wait_until(fn -> not File.exists?(path) end)
    end
  end

  test "removes the random file on request" do
    {:ok, path} = Plug.Upload.random_file("sample")
    File.open!(path)
    :ok = Plug.Upload.delete(path)
    wait_until(fn -> not File.exists?(path) end)
  end

  defp wait_until(fun) do
    if fun.() do
      :ok
    else
      Process.sleep(50)
      wait_until(fun)
    end
  end

  test "terminate removes all files" do
    {:ok, path} = Plug.Upload.random_file("sample")
    :ok = Plug.Upload.Terminator.terminate(:shutdown, [])
    refute File.exists?(path)
  end

  test "give_away/2 assigns ownership to other pid" do
    parent = self()

    {other_pid, other_ref} =
      spawn_monitor(fn ->
        receive do
          :exit -> nil
        end
      end)

    {pid, ref} =
      spawn_monitor(fn ->
        {:ok, path1} = Plug.Upload.random_file("sample")
        send(parent, {:path1, path1})
        File.open!(path1)

        {:ok, path2} = Plug.Upload.random_file("sample")
        send(parent, {:path2, path2})
        File.open!(path2)

        {:ok, path3} = Plug.Upload.random_file("sample")
        send(parent, {:path3, path3})
        File.open!(path3)

        :ok = Plug.Upload.give_away(path1, other_pid)
        :ok = Plug.Upload.give_away(path2, other_pid)
      end)

    path1 =
      receive do
        {:path1, path} -> path
      after
        1_000 -> flunk("didn't get a path")
      end

    path2 =
      receive do
        {:path2, path} -> path
      after
        1_000 -> flunk("didn't get a path")
      end

    path3 =
      receive do
        {:path3, path} -> path
      after
        1_000 -> flunk("didn't get a path")
      end

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        wait_until(fn -> not File.exists?(path3) end)
        assert File.exists?(path1)
        assert File.exists?(path2)
    end

    send(other_pid, :exit)

    receive do
      {:DOWN, ^other_ref, :process, ^other_pid, :normal} ->
        wait_until(fn -> not File.exists?(path1) end)
        wait_until(fn -> not File.exists?(path2) end)
    end
  end

  test "give_away/3 assigns ownership to other pid fro third party pid" do
    parent = self()

    {other_pid, other_ref} =
      spawn_monitor(fn ->
        receive do
          :exit -> nil
        end
      end)

    {pid, ref} =
      spawn_monitor(fn ->
        {:ok, path1} = Plug.Upload.random_file("sample")
        send(parent, {:path1, path1})
        File.open!(path1)

        {:ok, path2} = Plug.Upload.random_file("sample")
        send(parent, {:path2, path2})
        File.open!(path2)

        {:ok, path3} = Plug.Upload.random_file("sample")
        send(parent, {:path3, path3})
        File.open!(path3)

        assert_receive :done
      end)

    path1 =
      receive do
        {:path1, path} -> path
      after
        1_000 -> flunk("didn't get a path")
      end

    path2 =
      receive do
        {:path2, path} -> path
      after
        1_000 -> flunk("didn't get a path")
      end

    path3 =
      receive do
        {:path3, path} -> path
      after
        1_000 -> flunk("didn't get a path")
      end

    :ok = Plug.Upload.give_away(path1, other_pid, pid)
    :ok = Plug.Upload.give_away(path2, other_pid, pid)
    send(pid, :done)

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        wait_until(fn -> not File.exists?(path3) end)
        assert File.exists?(path1)
        assert File.exists?(path2)
    end

    send(other_pid, :exit)

    receive do
      {:DOWN, ^other_ref, :process, ^other_pid, :normal} ->
        wait_until(fn -> not File.exists?(path1) end)
        wait_until(fn -> not File.exists?(path2) end)
    end
  end

  test "give_away/3 assigns ownership to other pid which has existing uploads" do
    parent = self()

    {other_pid, other_ref} =
      spawn_monitor(fn ->
        {:ok, path} = Plug.Upload.random_file("recipient")
        send(parent, {:recipient, path})

        receive do
          :exit -> nil
        end
      end)

    path =
      receive do
        {:recipient, path} -> path
      after
        1_000 -> flunk("didn't get a path")
      end

    {pid, ref} =
      spawn_monitor(fn ->
        {:ok, path1} = Plug.Upload.random_file("sample")
        send(parent, {:path1, path1})
        File.open!(path1)

        :ok = Plug.Upload.give_away(path1, other_pid)
      end)

    path1 =
      receive do
        {:path1, path} -> path
      after
        1_000 -> flunk("didn't get a path")
      end

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        {:ok, _} = Plug.Upload.random_file("sample")

        assert File.exists?(path)
        assert File.exists?(path1)
    end

    send(other_pid, :exit)

    receive do
      {:DOWN, ^other_ref, :process, ^other_pid, :normal} ->
        wait_until(fn -> not File.exists?(path) end)
        wait_until(fn -> not File.exists?(path1) end)
    end
  end

  test "give_away with invalid path returns error" do
    result = Plug.Upload.give_away("/invalid/path", spawn(fn -> :ok end))
    assert result == {:error, :unknown_path}
  end

  test "give_away when target process dies during transfer" do
    {:ok, path} = Plug.Upload.random_file("target_dies")

    # Create a process that dies immediately
    pid = spawn(fn -> :ok end)

    # This should still work but file will be cleaned up when dead process is detected
    result = Plug.Upload.give_away(path, pid)
    assert result == :ok
    wait_until(fn -> not File.exists?(path) end)
  end

  test "routes uploads to correct partition based on process" do
    parent = self()
    num_processes = 10

    # Create uploads from different processes and verify they get different servers
    tasks =
      Enum.map(1..num_processes, fn i ->
        Task.async(fn ->
          {:ok, path} = Plug.Upload.random_file("partition_test_#{i}")
          server = PartitionSupervisor.whereis_name({Plug.Upload, self()})
          send(parent, {:result, i, path, server})
          path
        end)
      end)

    # Collect results
    results =
      Enum.map(1..num_processes, fn _ ->
        receive do
          {:result, i, path, server} -> {i, path, server}
        after
          1_000 -> flunk("didn't get result")
        end
      end)

    # Verify different processes got different servers (partitioning working)
    servers = Enum.map(results, fn {_, _, server} -> server end)
    assert length(Enum.uniq(servers)) > 1

    # Cleanup
    Enum.each(tasks, &Task.await/1)
  end
end
