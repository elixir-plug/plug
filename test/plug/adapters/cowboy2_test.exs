defmodule Plug.Adapters.Cowboy2Test do
  use ExUnit.Case

  @raise_message "plug_cowboy dependency missing"
  @missing_warning "Please add `{:plug_cowboy, \"~> 2.0\"}`"
  @deprecated_warning "using the Plug.Adapters.Cowboy2 adapter"
  @plug_cowboy_path Path.expand("../../fixtures/plug_cowboy.exs", __DIR__)

  setup do
    Code.require_file(@plug_cowboy_path)
    :ok
  end

  import ExUnit.CaptureIO

  describe "http/3" do
    test "raises and warns if the plug_cowboy is missing" do
      test_raise(fn -> Plug.Adapters.Cowboy2.http(__MODULE__, [], port: 8003) end)
    end

    test "proxies if Plug.Cowboy is defined" do
      test_deprecation(fn ->
        assert {:ok, :http} == Plug.Adapters.Cowboy2.http(__MODULE__, [], port: 8003)
      end)
    end
  end

  describe "https/3" do
    test "raises and warns if the plug_cowboy is missing" do
      test_raise(fn -> Plug.Adapters.Cowboy2.https(__MODULE__, [], port: 8003) end)
    end

    test "proxies if Plug.Cowboy is defined" do
      test_deprecation(fn ->
        assert {:ok, :https} == Plug.Adapters.Cowboy2.https(__MODULE__, [], port: 8003)
      end)
    end
  end

  describe "shutdown/1" do
    test "raises and warns if the plug_cowboy is missing" do
      test_raise(fn -> Plug.Adapters.Cowboy2.shutdown(:ref) end)
    end

    test "proxies if Plug.Cowboy is defined" do
      test_deprecation(fn ->
        assert {:ok, :shutdown} == Plug.Adapters.Cowboy2.shutdown(:ref)
      end)
    end
  end

  describe "child_spec/1" do
    test "raises and warns if the plug_cowboy is missing" do
      test_raise(fn -> Plug.Adapters.Cowboy2.child_spec([]) end)
    end

    test "proxies if Plug.Cowboy is defined" do
      test_deprecation(fn ->
        assert {:ok, :child_spec} == Plug.Adapters.Cowboy2.child_spec([])
      end)
    end
  end

  defp test_raise(fun) do
    unload_plug_cowboy()

    output =
      capture_io(:stderr, fn ->
        assert_raise(RuntimeError, @raise_message, fn ->
          fun.()
        end)
      end)

    assert output =~ @missing_warning
  end

  defp test_deprecation(fun) do
    output =
      capture_io(:stderr, fn ->
        fun.()
      end)

    assert output =~ @deprecated_warning
  end

  defp unload_plug_cowboy() do
    :code.delete(Plug.Cowboy)
    :code.purge(Plug.Cowboy)
    Code.unload_files([@plug_cowboy_path])
  end
end
