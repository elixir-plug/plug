defmodule Plug.Adapters.Cowboy2Test do
  use ExUnit.Case, async: true

  import Plug.Adapters.Cowboy2

  @moduletag :cowboy2

  def init([]) do
    [foo: :bar]
  end

  handler = {:_, [], Plug.Adapters.Cowboy2.Handler, {Plug.Adapters.Cowboy2Test, [foo: :bar]}}
  @dispatch [{:_, [], [handler]}]

  if function_exported?(Supervisor, :child_spec, 2) do
    test "supports Elixir v1.5 child specs" do
      spec = {Plug.Adapters.Cowboy2, [scheme: :http, plug: __MODULE__, options: [port: 4040]]}

      assert %{
               id: {:ranch_listener_sup, Plug.Adapters.Cowboy2Test.HTTP},
               modules: [:ranch_listener_sup],
               restart: :permanent,
               shutdown: :infinity,
               start: {:ranch_listener_sup, :start_link, _},
               type: :supervisor
             } = Supervisor.child_spec(spec, [])
    end

    test "the h2 alpn settings are added when using https" do
      options = [
        port: 4040,
        password: "cowboy",
        keyfile: Path.expand("../../fixtures/ssl/server.key", __DIR__),
        certfile: Path.expand("../../fixtures/ssl/server.cer", __DIR__)
      ]

      spec = {Plug.Adapters.Cowboy2, [scheme: :https, plug: __MODULE__, options: options]}

      %{start: {:ranch_listener_sup, :start_link, opts}} = Supervisor.child_spec(spec, [])

      assert [
               Plug.Adapters.Cowboy2Test.HTTPS,
               100,
               :ranch_ssl,
               transport_opts,
               :cowboy_tls,
               _proto_opts
             ] = opts

      assert Keyword.get(transport_opts, :alpn_preferred_protocols) == ["h2", "http/1.1"]
      assert Keyword.get(transport_opts, :next_protocols_advertised) == ["h2", "http/1.1"]
    end
  end

  test "builds args for cowboy dispatch" do
    assert [
             Plug.Adapters.Cowboy2Test.HTTP,
             [num_acceptors: 100, port: 4000, max_connections: 16_384],
             %{env: %{dispatch: @dispatch}}
           ] = args(:http, __MODULE__, [], [])
  end

  test "builds args with custom options" do
    assert [
             Plug.Adapters.Cowboy2Test.HTTP,
             [num_acceptors: 100, max_connections: 16_384, port: 3000, other: true],
             %{env: %{dispatch: @dispatch}}
           ] = args(:http, __MODULE__, [], port: 3000, other: true)
  end

  test "builds args with non 2-element tuple options" do
    assert [
             Plug.Adapters.Cowboy2Test.HTTP,
             [
               :inet6,
               {:raw, 1, 2, 3},
               num_acceptors: 100,
               max_connections: 16_384,
               port: 3000,
               other: true
             ],
             %{env: %{dispatch: @dispatch}}
           ] = args(:http, __MODULE__, [], [:inet6, {:raw, 1, 2, 3}, port: 3000, other: true])
  end

  test "builds args with protocol option" do
    assert [
             Plug.Adapters.Cowboy2Test.HTTP,
             [num_acceptors: 100, max_connections: 16_384, port: 3000],
             %{env: %{dispatch: @dispatch}, compress: true, timeout: 30_000}
           ] = args(:http, __MODULE__, [], port: 3000, compress: true, timeout: 30_000)

    assert [
             Plug.Adapters.Cowboy2Test.HTTP,
             [num_acceptors: 100, max_connections: 16_384, port: 3000],
             %{env: %{dispatch: @dispatch}, timeout: 30_000}
           ] = args(:http, __MODULE__, [], port: 3000, protocol_options: [timeout: 30_000])
  end

  test "builds args with num_acceptors option" do
    assert [
             Plug.Adapters.Cowboy2Test.HTTP,
             [max_connections: 16_384, port: 3000, num_acceptors: 5],
             %{env: %{dispatch: @dispatch}}
           ] = args(:http, __MODULE__, [], port: 3000, compress: true, num_acceptors: 5)
  end

  test "builds args with compress option" do
    assert [
             Plug.Adapters.Cowboy2Test.HTTP,
             [num_acceptors: 100, max_connections: 16_384, port: 3000],
             %{
               env: %{dispatch: @dispatch},
               stream_handlers: [:cowboy_compress_h, Plug.Adapters.Cowboy2.Stream]
             }
           ] = args(:http, __MODULE__, [], port: 3000, compress: true)
  end

  test "builds args with compress option fails if stream_handlers are set" do
    assert_raise(RuntimeError, ~r/set both compress and stream_handlers/, fn ->
      args(:http, __MODULE__, [], port: 3000, compress: true, stream_handlers: [:cowboy_stream_h])
    end)
  end

  test "builds args with single-atom protocol option" do
    assert [
             Plug.Adapters.Cowboy2Test.HTTP,
             [:inet6, num_acceptors: 100, max_connections: 16_384, port: 3000],
             %{env: %{dispatch: @dispatch}}
           ] = args(:http, __MODULE__, [], [:inet6, port: 3000])
  end

  test "builds child specs" do
    assert %{
             id: {:ranch_listener_sup, Plug.Adapters.Cowboy2Test.HTTP},
             modules: [:ranch_listener_sup],
             start: {:ranch_listener_sup, :start_link, _},
             restart: :permanent,
             shutdown: :infinity,
             type: :supervisor
           } = child_spec(scheme: :http, plug: __MODULE__, options: [])
  end
end
