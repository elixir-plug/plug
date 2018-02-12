defmodule Plug.Adapters.CowboyTest do
  use ExUnit.Case, async: true

  import Plug.Adapters.Cowboy

  @moduletag :cowboy1

  def init([]) do
    [foo: :bar]
  end

  @dispatch [
    {:_, [],
     [
       {:_, [], Plug.Adapters.Cowboy.Handler, {Plug.Adapters.CowboyTest, [foo: :bar]}}
     ]}
  ]

  if function_exported?(Supervisor, :child_spec, 2) do
    test "supports Elixir v1.5 child specs" do
      spec = {Plug.Adapters.Cowboy, [scheme: :http, plug: __MODULE__, options: [port: 4040]]}

      assert %{
               id: {:ranch_listener_sup, Plug.Adapters.CowboyTest.HTTP},
               modules: [:ranch_listener_sup],
               restart: :permanent,
               shutdown: :infinity,
               start: {:ranch_listener_sup, :start_link, _},
               type: :supervisor
             } = Supervisor.child_spec(spec, [])
    end
  end

  test "builds args for cowboy dispatch" do
    assert [
             Plug.Adapters.CowboyTest.HTTP,
             100,
             [port: 4000, max_connections: 16_384],
             [env: [dispatch: @dispatch], onresponse: _]
           ] = args(:http, __MODULE__, [], [])
  end

  test "builds args with custom options" do
    assert [
             Plug.Adapters.CowboyTest.HTTP,
             25,
             [max_connections: 16_384, port: 3000, other: true],
             [env: [dispatch: @dispatch], onresponse: _]
           ] = args(:http, __MODULE__, [], port: 3000, acceptors: 25, other: true)
  end

  test "builds args with non 2-element tuple options" do
    assert [
             Plug.Adapters.CowboyTest.HTTP,
             25,
             [:inet6, {:raw, 1, 2, 3}, max_connections: 16_384, port: 3000, other: true],
             [env: [dispatch: @dispatch], onresponse: _]
           ] =
             args(:http, __MODULE__, [], [
               :inet6,
               {:raw, 1, 2, 3},
               port: 3000,
               acceptors: 25,
               other: true
             ])
  end

  test "builds args with protocol option" do
    assert [
             Plug.Adapters.CowboyTest.HTTP,
             25,
             [max_connections: 16_384, port: 3000],
             [env: [dispatch: @dispatch], onresponse: _, compress: true, timeout: 30_000]
           ] =
             args(
               :http,
               __MODULE__,
               [],
               port: 3000,
               acceptors: 25,
               compress: true,
               timeout: 30_000
             )

    assert [
             Plug.Adapters.CowboyTest.HTTP,
             25,
             [max_connections: 16_384, port: 3000],
             [env: [dispatch: @dispatch], onresponse: _, timeout: 30_000]
           ] =
             args(
               :http,
               __MODULE__,
               [],
               port: 3000,
               acceptors: 25,
               protocol_options: [timeout: 30_000]
             )
  end

  test "builds args with single-atom protocol option" do
    assert [
             Plug.Adapters.CowboyTest.HTTP,
             25,
             [:inet6, max_connections: 16_384, port: 3000],
             [env: [dispatch: @dispatch], onresponse: _]
           ] = args(:http, __MODULE__, [], [:inet6, port: 3000, acceptors: 25])
  end

  test "builds child specs" do
    assert {id, start, :permanent, :infinity, :supervisor, [:ranch_listener_sup]} =
             child_spec(:http, __MODULE__, [], [])

    assert id == {:ranch_listener_sup, Plug.Adapters.CowboyTest.HTTP}
    assert {:ranch_listener_sup, :start_link, _} = start
  end

  describe "onresponse handling" do
    test "includes the default onresponse handler" do
      assert [
               Plug.Adapters.CowboyTest.HTTP,
               _,
               _,
               [env: [dispatch: @dispatch], onresponse: on_response]
             ] = args(:http, __MODULE__, [], [])

      assert is_function(on_response)
    end

    test "elides the default onresponse handler if log_error_on_incomplete_requests is set to false" do
      assert [Plug.Adapters.CowboyTest.HTTP, _, _, [env: [dispatch: @dispatch]]] =
               args(:http, __MODULE__, [], log_error_on_incomplete_requests: false)
    end

    test "elides the default onresponse handler if log_error_on_incomplete_requests is set to false and includes the user-provided onresponse handler" do
      my_onresponse = fn _, _, _, req -> req end

      assert [
               Plug.Adapters.CowboyTest.HTTP,
               _,
               _,
               [env: [dispatch: @dispatch], onresponse: on_response]
             ] =
               args(
                 :http,
                 __MODULE__,
                 [],
                 log_error_on_incomplete_requests: false,
                 protocol_options: [onresponse: my_onresponse]
               )

      assert is_function(on_response)
      assert on_response == my_onresponse
    end

    test "elides the default onresponse handler if log_error_on_incomplete_requests is set to false and handles user-provided onresponse tuple " do
      my_onresponse = {Plug.Adapters.CowboyTest, :my_onresponse_handler}

      assert [
               Plug.Adapters.CowboyTest.HTTP,
               _,
               _,
               [env: [dispatch: @dispatch], onresponse: default_response]
             ] = args(:http, __MODULE__, [], [])

      assert [
               Plug.Adapters.CowboyTest.HTTP,
               _,
               _,
               [env: [dispatch: @dispatch], onresponse: on_response]
             ] =
               args(
                 :http,
                 __MODULE__,
                 [],
                 log_error_on_incomplete_requests: false,
                 protocol_options: [onresponse: my_onresponse]
               )

      assert is_function(on_response)
      assert on_response != default_response
    end

    test "includes the default onresponse handler and the user-provided onresponse handler" do
      # Grab a ref to the default onresponse handler
      assert [
               Plug.Adapters.CowboyTest.HTTP,
               _,
               _,
               [env: [dispatch: @dispatch], onresponse: default_response]
             ] = args(:http, __MODULE__, [], [])

      my_onresponse = fn _, _, _, req -> req end

      assert [
               Plug.Adapters.CowboyTest.HTTP,
               _,
               _,
               [env: [dispatch: @dispatch], onresponse: on_response]
             ] = args(:http, __MODULE__, [], protocol_options: [onresponse: my_onresponse])

      assert is_function(on_response)
      assert on_response != default_response
      assert on_response != my_onresponse
    end

    test "includes the default onresponse handler and handles the user-provided onresponse handler tuple" do
      # Grab a ref to the default onresponse handler
      assert [
               Plug.Adapters.CowboyTest.HTTP,
               _,
               _,
               [env: [dispatch: @dispatch], onresponse: default_response]
             ] = args(:http, __MODULE__, [], [])

      my_onresponse = {Plug.Adapters.CowboyTest, :my_onresponse_handler}

      assert [
               Plug.Adapters.CowboyTest.HTTP,
               _,
               _,
               [env: [dispatch: @dispatch], onresponse: on_response]
             ] = args(:http, __MODULE__, [], protocol_options: [onresponse: my_onresponse])

      assert is_function(on_response)
      assert on_response != default_response
      assert on_response != my_onresponse
    end
  end

  defmodule MyPlug do
    def init(opts), do: opts
  end

  test "errors when trying to run on https" do
    assert_raise ArgumentError, ~r/missing option :key\/:keyfile/, fn ->
      Plug.Adapters.Cowboy.https(MyPlug, [], [])
    end

    message = ~r/ssl\/key\.pem required by SSL's :keyfile either does not exist/

    assert_raise ArgumentError, message, fn ->
      Plug.Adapters.Cowboy.https(
        MyPlug,
        [],
        keyfile: "priv/ssl/key.pem",
        certfile: "priv/ssl/cert.pem",
        otp_app: :plug
      )
    end
  end
end
