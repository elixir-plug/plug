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
    :ok = Plug.Upload.terminate(:shutdown, [])
    refute File.exists?(path)
  end

  test "give_away/3 assigns ownership to other pid" do
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
end
