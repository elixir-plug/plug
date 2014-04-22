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
    If this option is used, the plug given plug won't be initialized
    nor dispatched to (and doing so becomes the user responsibility).

  * `:ref` - the reference name to be used.
    Defaults to `plug.HTTP` (http) and `plug.HTTPS` (https).
    This is the value that needs to be given on shutdown.

  * `:compress` - Cowboy will attempt to compress the response body.

  """

  # Used for testing of cowboy.
  @doc false
  def args(scheme, plug, opts, options) do
    options
    |> Keyword.put_new(:ref, build_ref(plug, scheme))
    |> Keyword.put_new(:dispatch, options[:dispatch] || dispatch_for(plug, opts))
    |> normalize_options(scheme)
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
  def http(plug, opts, options \\ []) do
    run(:http, plug, opts, options)
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
        keyfile: "ssl/key.pem",
        certfile: "ssl/cert.pem"

      # The interface above can be shutdown with
      Plug.Adapters.Cowboy.shutdown MyPlug.HTTPS

  """
  def https(plug, opts, options \\ []) do
    :application.start(:asn1)
    :application.start(:public_key)
    :application.start(:ssl)
    run(:https, plug, opts, options)
  end

  @doc """
  Shutdowns the given reference.
  """
  def shutdown(ref) do
    :cowboy.stop_listener(ref)
  end

  @doc """
  Returns a child_spec to be supervised by your application.
  """
  def child_spec(scheme, plug, opts, options \\ []) do
    [ref, nb_acceptors, trans_opts, proto_opts] = args(scheme, plug, opts, options)
    ranch_module = case scheme do
      :http -> :ranch_tcp
      :https -> :ranch_ssl
    end
    :ranch.child_spec(ref, nb_acceptors, ranch_module, trans_opts, :cowboy_protocol, proto_opts)
  end

  ## Helpers

  @http_options  [port: 4000]
  @https_options [port: 4040]
  @not_options [:acceptors, :dispatch, :ref, :otp_app, :compress]

  defp run(scheme, plug, opts, options) do
    :application.start(:crypto)
    :application.start(:ranch)
    :application.start(:cowlib)
    :application.start(:cowboy)
    apply(:cowboy, :"start_#{scheme}", args(scheme, plug, opts, options))
  end

  defp normalize_options(options, :http) do
    Keyword.merge @http_options, options
  end

  defp normalize_options(options, :https) do
    options = Keyword.merge @https_options, options
    options = Enum.reduce [:keyfile, :certfile, :cacertfile], options, &normalize_ssl_file(&1, &2)
    options = Enum.reduce [:password], options, &to_char_list(&2, &1)
    options
  end

  defp to_args(options) do
    ref       = options[:ref]
    acceptors = options[:acceptors] || 100
    dispatch  = :cowboy_router.compile(options[:dispatch])
    compress  = options[:compress] || false
    options   = Keyword.drop(options, @not_options)
    [ref, acceptors, options, [env: [dispatch: dispatch], compress: compress]]
  end

  defp build_ref(plug, scheme) do
    Module.concat(plug, scheme |> to_string |> String.upcase)
  end

  defp dispatch_for(plug, opts) do
    opts = plug.init(opts)
    [{:_, [ {:_, Plug.Adapters.Cowboy.Handler, {plug, opts}} ]}]
  end

  defp normalize_ssl_file(key, options) do
    value = options[key]

    cond do
      nil?(value) ->
        options
      Path.type(value) == :absolute ->
        Keyword.put(options, key, to_char_list(value))
      true ->
        new = Path.expand(value, otp_app(options)) |> to_char_list
        Keyword.put(options, key, new)
    end
  end

  defp otp_app(options) do
    if app = options[:otp_app] do
      :code.priv_dir(app)
    else
      raise ArgumentError, message: "to use relative certificate with https, the :otp_app " <>
                                    "option needs to be given when invoking the handler"
    end
  end

  defp to_char_list(options, key) do
    if value = options[key] do
      Keyword.put options, key, to_char_list(value)
    else
      options
    end
  end
end
