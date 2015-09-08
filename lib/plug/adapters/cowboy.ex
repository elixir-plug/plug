defmodule Plug.Adapters.Cowboy do
  @moduledoc """
  Adapter interface to the Cowboy webserver.

  ## Options

  * `:ip` - the ip to bind the server to.
    Must be a tuple in the format `{x, y, z, w}`.

  * `:port` - the port to run the server.
    Defaults to 4000 (http) and 4040 (https).

  * `:acceptors` - the number of acceptors for the listener.
    Defaults to 100.

  * `:max_connections` - max number of connections supported.
    Defaults to `:infinity`.

  * `:dispatch` - manually configure Cowboy's dispatch.
    If this option is used, the given plug won't be initialized
    nor dispatched to (and doing so becomes the user's responsibility).

  * `:ref` - the reference name to be used.
    Defaults to `plug.HTTP` (http) and `plug.HTTPS` (https).
    This is the value that needs to be given on shutdown.

  * `:compress` - Cowboy will attempt to compress the response body.

  * `:timeout` - Time in ms with no requests before Cowboy closes the connection.

  """

  # Made public with @doc false for testing.
  @doc false
  def args(scheme, plug, opts, cowboy_options) do
    cowboy_options
    |> Keyword.put_new(:ref, build_ref(plug, scheme))
    |> Keyword.put_new(:dispatch, cowboy_options[:dispatch] || dispatch_for(plug, opts))
    |> normalize_cowboy_options(scheme)
    |> to_args()
  end

  @doc """
  Run cowboy under http.

  ## Example

      # Starts a new interface
      Plug.Adapters.Cowboy.http MyPlug, [], port: 80

      # The interface above can be shutdown with
      Plug.Adapters.Cowboy.shutdown MyPlug.HTTP

  """
  @spec http(module(), Keyword.t, Keyword.t) ::
        {:ok, pid} | {:error, :eaddrinuse} | {:error, term}
  def http(plug, opts, cowboy_options \\ []) do
    run(:http, plug, opts, cowboy_options)
  end

  @doc """
  Run cowboy under https.

  Besides the options described in the module documentation,
  this module also accepts all options defined in [the `ssl`
  erlang module] (http://www.erlang.org/doc/man/ssl.html),
  like keyfile, certfile, cacertfile and others.

  The certificate files can be given as a relative path.
  For such, the `:otp_app` option must also be given and
  certificates will be looked from the priv directory of
  the given application.

  ## Example

      # Starts a new interface
      Plug.Adapters.Cowboy.https MyPlug, [],
        port: 443,
        password: "SECRET",
        otp_app: :my_app,
        keyfile: "priv/ssl/key.pem",
        certfile: "priv/ssl/cert.pem"

      # The interface above can be shutdown with
      Plug.Adapters.Cowboy.shutdown MyPlug.HTTPS

  """
  @spec https(module(), Keyword.t, Keyword.t) ::
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
  Returns a child spec to be supervised by your application.
  """
  def child_spec(scheme, plug, opts, cowboy_options \\ []) do
    [ref, nb_acceptors, trans_opts, proto_opts] = args(scheme, plug, opts, cowboy_options)
    ranch_module = case scheme do
      :http  -> :ranch_tcp
      :https -> :ranch_ssl
    end
    :ranch.child_spec(ref, nb_acceptors, ranch_module, trans_opts, :cowboy_protocol, proto_opts)
  end

  ## Helpers

  @http_cowboy_options  [port: 4000]
  @https_cowboy_options [port: 4040]
  @not_cowboy_options [:acceptors, :dispatch, :ref, :otp_app, :compress, :timeout]

  defp run(scheme, plug, opts, cowboy_options) do
    case Application.ensure_all_started(:cowboy) do
      {:ok, _} ->
        :ok
      {:error, {:cowboy, _}} ->
        raise "could not start the cowboy application. Please ensure it is listed " <>
              "as a dependency both in deps and application in your mix.exs"
    end
    apply(:cowboy, :"start_#{scheme}", args(scheme, plug, opts, cowboy_options))
  end

  defp normalize_cowboy_options(cowboy_options, :http) do
    Keyword.merge @http_cowboy_options, cowboy_options
  end

  defp normalize_cowboy_options(cowboy_options, :https) do
    assert_ssl_options(cowboy_options)
    cowboy_options = Keyword.merge @https_cowboy_options, cowboy_options
    cowboy_options = Enum.reduce [:keyfile, :certfile, :cacertfile], cowboy_options, &normalize_ssl_file(&1, &2)
    cowboy_options = Enum.reduce [:password], cowboy_options, &to_char_list(&2, &1)
    cowboy_options
  end

  defp to_args(cowboy_options) do
    ref       = cowboy_options[:ref]
    acceptors = cowboy_options[:acceptors] || 100
    dispatch  = :cowboy_router.compile(cowboy_options[:dispatch])
    compress  = cowboy_options[:compress] || false
    timeout_option    = if cowboy_options[:timeout] do [timeout: cowboy_options[:timeout]] else [] end
    transport_options = [env: [dispatch: dispatch], compress: compress] ++ timeout_option
    cowboy_options    = Keyword.drop(cowboy_options, @not_cowboy_options)

    [ref, acceptors, cowboy_options, transport_options]
  end

  defp build_ref(plug, scheme) do
    Module.concat(plug, scheme |> to_string |> String.upcase)
  end

  defp dispatch_for(plug, opts) do
    opts = plug.init(opts)
    [{:_, [ {:_, Plug.Adapters.Cowboy.Handler, {plug, opts}} ]}]
  end

  defp normalize_ssl_file(key, cowboy_options) do
    value = cowboy_options[key]

    cond do
      is_nil(value) ->
        cowboy_options
      Path.type(value) == :absolute ->
        put_ssl_file cowboy_options, key, value
      true ->
        put_ssl_file cowboy_options, key, Path.expand(value, otp_app(cowboy_options))
    end
  end

  defp assert_ssl_options(cowboy_options) do
    unless Keyword.has_key?(cowboy_options, :key) or
           Keyword.has_key?(cowboy_options, :keyfile) do
      fail "missing option :key/:keyfile"
    end
    unless Keyword.has_key?(cowboy_options, :cert) or
           Keyword.has_key?(cowboy_options, :certfile) do
      fail "missing option :cert/:certfile"
    end
  end

  defp put_ssl_file(cowboy_options, key, value) do
    value = to_char_list(value)
    unless File.exists?(value) do
      fail "the file #{value} required by SSL's #{inspect key} does not exist"
    end
    Keyword.put(cowboy_options, key, value)
  end

  defp otp_app(cowboy_options) do
    if app = cowboy_options[:otp_app] do
      Application.app_dir(app)
    else
      fail "to use a relative certificate with https, the :otp_app " <>
           "option needs to be given to the adapter"
    end
  end

  defp to_char_list(cowboy_options, key) do
    if value = cowboy_options[key] do
      Keyword.put cowboy_options, key, to_char_list(value)
    else
      cowboy_options
    end
  end

  defp fail(message) do
    raise ArgumentError, message: "could not start Cowboy adapter, " <> message
  end
end
