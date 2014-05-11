defmodule Plug.UploadTest do
  use ExUnit.Case, async: true

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
