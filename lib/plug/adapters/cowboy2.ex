defmodule Plug.Adapters.Cowboy2 do
  @moduledoc """
  Adapter interface to the Cowboy2 webserver.

  ## Options

    * `:ip` - the ip to bind the server to.
      Must be either a tuple in the format `{a, b, c, d}` with each value in `0..255` for IPv4
      or a tuple in the format `{a, b, c, d, e, f, g, h}` with each value in `0..65535` for IPv6.

    * `:port` - the port to run the server.
      Defaults to 4000 (http) and 4040 (https).

    * `:acceptors` - the number of acceptors for the listener.
      Defaults to 100.

    * `:max_connections` - max number of connections supported.
      Defaults to `16_384`.

    * `:dispatch` - manually configure Cowboy's dispatch.
      If this option is used, the given plug won't be initialized
      nor dispatched to (and doing so becomes the user's responsibility).

    * `:ref` - the reference name to be used.
      Defaults to `plug.HTTP` (http) and `plug.HTTPS` (https).
      This is the value that needs to be given on shutdown.

    * `:compress` - Cowboy will attempt to compress the response body.
      Defaults to false.

    * `:timeout` - Time in ms with no requests before Cowboy closes the connection.
      Defaults to 5000ms.

    * `:protocol_options` - Specifies remaining protocol options,
      see [Cowboy docs](https://ninenines.eu/docs/en/cowboy/2.0/manual/cowboy_http/).

  All other options are given to the underlying transport.
  """

  require Logger

  # Made public with @doc false for testing.
  @doc false
  def args(scheme, plug, plug_opts, cowboy_options) do
    {cowboy_options, non_keyword_options} =
      enum_split_with(cowboy_options, &(is_tuple(&1) and tuple_size(&1) == 2))

    cowboy_options
    |> Keyword.put_new(:max_connections, 16_384)
    |> set_compress()
    |> normalize_cowboy_options(scheme)
    |> to_args(scheme, plug, plug_opts, non_keyword_options)
  end

  @doc """
  Runs cowboy under http.

  ## Example

      # Starts a new interface
      Plug.Adapters.Cowboy2.http MyPlug, [], port: 80

      # The interface above can be shutdown with
      Plug.Adapters.Cowboy2.shutdown MyPlug.HTTP

  """
  @spec http(module(), Keyword.t(), Keyword.t()) ::
          {:ok, pid} | {:error, :eaddrinuse} | {:error, term}
  def http(plug, opts, cowboy_options \\ []) do
    run(:http, plug, opts, cowboy_options)
  end

  @doc """
  Runs cowboy under https.

  Besides the options described in the module documentation,
  this module also accepts all options defined in [the `ssl`
  erlang module] (http://www.erlang.org/doc/man/ssl.html),
  like keyfile, certfile, cacertfile, dhfile and others.

  The certificate files can be given as a relative path.
  For such, the `:otp_app` option must also be given and
  certificates will be looked from the priv directory of
  the given application.

  ## Example

      # Starts a new interface
      Plug.Adapters.Cowboy2.https MyPlug, [],
        port: 443,
        password: "SECRET",
        otp_app: :my_app,
        keyfile: "priv/ssl/key.pem",
        certfile: "priv/ssl/cert.pem",
        dhfile: "priv/ssl/dhparam.pem"

      # The interface above can be shutdown with
      Plug.Adapters.Cowboy2.shutdown MyPlug.HTTPS

  """
  @spec https(module(), Keyword.t(), Keyword.t()) ::
          {:ok, pid} | {:error, :eaddrinuse} | {:error, term}
  def https(plug, opts, cowboy_options \\ []) do
    Application.ensure_all_started(:ssl)
    run(:https, plug, opts, cowboy_options)
  end

  @doc """
  Shutdowns the given reference.
  """
  def shutdown(ref) do
    :cowboy.stop_listener(ref)
  end

  @doc """
  A function for starting a Cowboy2 server under Elixir v1.5 supervisors.

  It expects three options:

    * `:scheme` - either `:http` or `:https`
    * `:plug` - such as MyPlug or {MyPlug, plug_opts}
    * `:options` - the server options as specified in the module documentation

  ## Examples

  Assuming your Plug module is named `MyApp` you can add it to your
  supervision tree by using this function:

      children = [
        {Plug.Adapters.Cowboy2, scheme: :http, plug: MyApp, options: [port: 4040]}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  """
  def child_spec(opts) do
    :ok = verify_cowboy_version()

    scheme = Keyword.fetch!(opts, :scheme)
    cowboy_opts = Keyword.get(opts, :options, [])

    {plug, plug_opts} =
      case Keyword.fetch!(opts, :plug) do
        {_, _} = tuple -> tuple
        plug -> {plug, []}
      end

    cowboy_args = args(scheme, plug, plug_opts, cowboy_opts)
    [ref, transport_opts, proto_opts] = cowboy_args

    {ranch_module, cowboy_protocol, transport_opts} =
      case scheme do
        :http ->
          {:ranch_tcp, :cowboy_clear, transport_opts}

        :https ->
          transport_opts =
            transport_opts
            |> Keyword.put_new(:next_protocols_advertised, ["h2", "http/1.1"])
            |> Keyword.put_new(:alpn_preferred_protocols, ["h2", "http/1.1"])

          {:ranch_ssl, :cowboy_tls, transport_opts}
      end

    num_acceptors = Keyword.get(transport_opts, :num_acceptors, 100)

    %{
      id: {:ranch_listener_sup, ref},
      start:
        {:ranch_listener_sup, :start_link,
         [
           ref,
           num_acceptors,
           ranch_module,
           transport_opts,
           cowboy_protocol,
           proto_opts
         ]},
      restart: :permanent,
      shutdown: :infinity,
      type: :supervisor,
      modules: [:ranch_listener_sup]
    }
  end

  ## Helpers

  @protocol_options [:timeout, :compress, :stream_handlers]

  defp run(scheme, plug, opts, cowboy_options) do
    case Application.ensure_all_started(:cowboy) do
      {:ok, _} ->
        verify_cowboy_version()

      {:error, {:cowboy, _}} ->
        raise "could not start the Cowboy application. Please ensure it is listed as a dependency in your mix.exs"
    end

    start =
      case scheme do
        :http -> :start_clear
        :https -> :start_tls
        other -> :erlang.error({:badarg, [other]})
      end

    apply(:cowboy, start, args(scheme, plug, opts, cowboy_options))
  end

  @default_stream_handlers [Plug.Adapters.Cowboy2.Stream]

  defp set_compress(cowboy_options) do
    compress = Keyword.get(cowboy_options, :compress)
    stream_handlers = Keyword.get(cowboy_options, :stream_handlers)

    case {compress, stream_handlers} do
      {true, nil} ->
        Keyword.put_new(cowboy_options, :stream_handlers, [
          :cowboy_compress_h | @default_stream_handlers
        ])

      {true, _} ->
        raise "cannot set both compress and stream_handlers at once. " <>
                "If you wish to set compress, please add `:cowboy_compress_h` to your stream handlers."

      _ ->
        cowboy_options
    end
  end

  defp normalize_cowboy_options(cowboy_options, :http) do
    Keyword.put_new(cowboy_options, :port, 4000)
  end

  defp normalize_cowboy_options(cowboy_options, :https) do
    assert_ssl_options(cowboy_options)
    cowboy_options = Keyword.put_new(cowboy_options, :port, 4040)
    ssl_opts = [:keyfile, :certfile, :cacertfile, :dhfile]

    cowboy_options = Enum.reduce(ssl_opts, cowboy_options, &normalize_ssl_file(&1, &2))
    Enum.reduce([:password], cowboy_options, &to_charlist(&2, &1))
  end

  defp to_args(opts, scheme, plug, plug_opts, non_keyword_opts) do
    opts = Keyword.delete(opts, :otp_app)
    {ref, opts} = Keyword.pop(opts, :ref)
    {dispatch, opts} = Keyword.pop(opts, :dispatch)
    {num_acceptors, opts} = Keyword.pop(opts, :acceptors, 100)
    {protocol_options, opts} = Keyword.pop(opts, :protocol_options, [])

    dispatch = :cowboy_router.compile(dispatch || dispatch_for(plug, plug_opts))
    {extra_options, transport_options} = Keyword.split(opts, @protocol_options)

    extra_options = Keyword.put_new(extra_options, :stream_handlers, @default_stream_handlers)
    protocol_and_extra_options = :maps.from_list(protocol_options ++ extra_options)
    protocol_options = Map.merge(%{env: %{dispatch: dispatch}}, protocol_and_extra_options)
    transport_options = Keyword.put_new(transport_options, :num_acceptors, num_acceptors)

    [ref || build_ref(plug, scheme), non_keyword_opts ++ transport_options, protocol_options]
  end

  defp build_ref(plug, scheme) do
    Module.concat(plug, scheme |> to_string |> String.upcase())
  end

  defp dispatch_for(plug, opts) do
    opts = plug.init(opts)
    [{:_, [{:_, Plug.Adapters.Cowboy2.Handler, {plug, opts}}]}]
  end

  defp normalize_ssl_file(key, cowboy_options) do
    value = cowboy_options[key]

    cond do
      is_nil(value) ->
        cowboy_options

      Path.type(value) == :absolute ->
        put_ssl_file(cowboy_options, key, value)

      true ->
        put_ssl_file(cowboy_options, key, Path.expand(value, otp_app(cowboy_options)))
    end
  end

  defp assert_ssl_options(cowboy_options) do
    has_sni? =
      Keyword.has_key?(cowboy_options, :sni_hosts) or Keyword.has_key?(cowboy_options, :sni_fun)

    has_key? =
      Keyword.has_key?(cowboy_options, :key) or Keyword.has_key?(cowboy_options, :keyfile)

    has_cert? =
      Keyword.has_key?(cowboy_options, :cert) or Keyword.has_key?(cowboy_options, :certfile)

    cond do
      has_sni? -> :ok
      !has_key? -> fail("missing option :key/:keyfile")
      !has_cert? -> fail("missing option :cert/:certfile")
      true -> :ok
    end
  end

  defp put_ssl_file(cowboy_options, key, value) do
    value = to_charlist(value)

    unless File.exists?(value) do
      fail(
        "the file #{value} required by SSL's #{inspect(key)} either does not exist, " <>
          "or the application does not have permission to access it"
      )
    end

    Keyword.put(cowboy_options, key, value)
  end

  defp otp_app(cowboy_options) do
    if app = cowboy_options[:otp_app] do
      Application.app_dir(app)
    else
      fail(
        "to use a relative certificate with https, the :otp_app " <>
          "option needs to be given to the adapter"
      )
    end
  end

  defp to_charlist(cowboy_options, key) do
    if value = cowboy_options[key] do
      Keyword.put(cowboy_options, key, to_charlist(value))
    else
      cowboy_options
    end
  end

  defp fail(message) do
    raise ArgumentError, message: "could not start Cowboy2 adapter, " <> message
  end

  defp verify_cowboy_version do
    case Application.spec(:cowboy, :vsn) do
      '2.' ++ _ ->
        :ok

      vsn ->
        raise "you are using Plug.Adapters.Cowboy (for Cowboy 1) but your current Cowboy " <>
                "version is #{vsn}. Please update your mix.exs file accordingly"
    end
  end

  # TODO: Remove once we depend on Elixir ~> 1.4.
  Code.ensure_loaded(Enum)
  split_with = if function_exported?(Enum, :split_with, 2), do: :split_with, else: :partition
  defp enum_split_with(enum, fun), do: apply(Enum, unquote(split_with), [enum, fun])
end
