defmodule Plug.Adapters.CowboyTest.Dummy do
  def init([]) do
    [foo: :bar]
  end
end

defmodule Plug.Adapters.CowboyTest do
  use ExUnit.Case

  import Plug.Adapters.Cowboy

  def init([]) do
    [foo: :bar]
  end

  def start_server(ref) do
    result = http(ref, [], [])
    on_exit fn ->
      :cowboy.stop_listener(ref.HTTP)
    end
    result
  end

  @dispatch [{:_, [], [{:_, [], Plug.Adapters.Cowboy.Handler, {Plug.Adapters.CowboyTest, [foo: :bar]}}]}]

  test "starting a connection successfully" do
    { status, _ } = start_server(__MODULE__)
    assert status == :ok
  end

  test "returns {:error, :eaddrinuse} when binding to a port already in use" do
    start_server(Plug.Adapters.CowboyTest.Dummy)
    {:error, code} = start_server(__MODULE__)
    assert code == :eaddrinuse
  end

  test "builds args for cowboy dispatch" do
    assert args(:http, __MODULE__, [], []) ==
           [Plug.Adapters.CowboyTest.HTTP,
            100,
            [port: 4000],
            [env: [dispatch: @dispatch], compress: false]]
  end

  test "builds args with custom options" do
    assert args(:http, __MODULE__, [], [port: 3000, acceptors: 25]) ==
           [Plug.Adapters.CowboyTest.HTTP,
            25,
            [port: 3000],
            [env: [dispatch: @dispatch], compress: false]]
  end

  test "builds child specs" do
    args = [Plug.Adapters.CowboyTest.HTTP,
            100,
            :ranch_tcp,
            [port: 4000],
            :cowboy_protocol,
            [env: [dispatch: @dispatch], compress: false]]

    assert child_spec(:http, __MODULE__, [], []) ==
           {{:ranch_listener_sup, Plug.Adapters.CowboyTest.HTTP},
            {:ranch_listener_sup, :start_link, args},
            :permanent,
            :infinity,
            :supervisor,
            [:ranch_listener_sup]}
  end
end
