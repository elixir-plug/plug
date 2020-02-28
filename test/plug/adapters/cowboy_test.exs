defmodule Plug.Adapters.CowboyTest do
  use ExUnit.Case

  @raise_message "plug_cowboy dependency missing"
  @missing_warning "{:plug_cowboy, \"~> 1.0\"}"
  @plug_cowboy_path Path.expand("../../fixtures/plug_cowboy.exs", __DIR__)

  setup do
    Code.require_file(@plug_cowboy_path)
    :ok
  end

  import ExUnit.CaptureIO

  describe "http/3" do
    test "raises and warns if the plug_cowboy is missing" do
      test_raise(fn -> Plug.Adapters.Cowboy.http(__MODULE__, [], port: 8003) end)
    end

    test "proxies if Plug.Cowboy is defined" do
      assert {:ok, :http} == Plug.Adapters.Cowboy.http(__MODULE__, [], port: 8003)
    end
  end

  describe "https/3" do
    test "raises and warns if the plug_cowboy is missing" do
      test_raise(fn -> Plug.Adapters.Cowboy.https(__MODULE__, [], port: 8003) end)
    end

    test "proxies if Plug.Cowboy is defined" do
      assert {:ok, :https} == Plug.Adapters.Cowboy.https(__MODULE__, [], port: 8003)
    end
  end

  describe "shutdown/1" do
    test "raises and warns if the plug_cowboy is missing" do
      test_raise(fn -> Plug.Adapters.Cowboy.shutdown(:ref) end)
    end

    test "proxies if Plug.Cowboy is defined" do
      assert {:ok, :shutdown} == Plug.Adapters.Cowboy.shutdown(:ref)
    end
  end

  describe "child_spec/4" do
    test "raises and warns if the plug_cowboy is missing" do
      test_raise(fn -> Plug.Adapters.Cowboy.child_spec(:http, __MODULE__, [], []) end)
    end

    test "proxies if Plug.Cowboy is defined" do
      assert {:ok, :child_spec} == Plug.Adapters.Cowboy.child_spec([])
      {:ok, :child_spec} = Plug.Adapters.Cowboy.child_spec(:http, __MODULE__, [], [])
    end
  end

  describe "child_spec/1" do
    test "raises and warns if the plug_cowboy is missing" do
      test_raise(fn -> Plug.Adapters.Cowboy.child_spec([]) end)
    end

    test "proxies if Plug.Cowboy is defined" do
      assert {:ok, :child_spec} == Plug.Adapters.Cowboy.child_spec([])
    end
  end

  defp test_raise(fun) do
    unload_plug_cowboy()

    output =
      capture_io(:stderr, fn ->
        Process.flag(:trap_exit, true)
        pid = spawn_link(fun)
        assert_receive({:EXIT, ^pid, @raise_message})
      end)

    assert output =~ @missing_warning
  end

  defp unload_plug_cowboy() do
    :code.delete(Plug.Cowboy)
    :code.purge(Plug.Cowboy)
    Code.unrequire_files([@plug_cowboy_path])
  end
end
