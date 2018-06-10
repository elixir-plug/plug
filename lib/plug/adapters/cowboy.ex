defmodule Plug.Adapters.Cowboy do
  @moduledoc """
  Adapter interface to the Cowboy webserver.

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

    * `:log_error_on_incomplete_requests` - An error is logged when the response status code is 400 and
      no headers are set in the request.
      Defaults to true.

    * `:protocol_options` - Specifies remaining protocol options,
      see [Cowboy protocol docs](http://ninenines.eu/docs/en/cowboy/1.0/manual/cowboy_protocol/).

  All other options are given to the underlying transport. When running
  on HTTPS, any SSL configuration should be given directly to the adapter.
  See `https/3` for an example and read `Plug.SSL.configure/1` to understand
  about our SSL defaults.
  """

  require Logger

  # Made public with @doc false for testing.
  @doc false
  def args(scheme, plug, opts, cowboy_options) do
    {cowboy_options, non_keyword_options} =
      enum_split_with(cowboy_options, &(is_tuple(&1) and tuple_size(&1) == 2))

    cowboy_options
    |> Keyword.put_new(:max_connections, 16_384)
    |> Keyword.put_new(:ref, build_ref(plug, scheme))
    |> Keyword.put_new(:dispatch, cowboy_options[:dispatch] || dispatch_for(plug, opts))
    |> normalize_cowboy_options(scheme)
    |> to_args(non_keyword_options)
  end

  @doc """
  Runs cowboy under http.

  ## Example

      # Starts a new interface
      Plug.Adapters.Cowboy.http MyPlug, [], port: 80

      # The interface above can be shutdown with
      Plug.Adapters.Cowboy.shutdown MyPlug.HTTP

  """
  @spec http(module(), Keyword.t(), Keyword.t()) ::
          {:ok, pid} | {:error, :eaddrinuse} | {:error, term}
  def http(plug, opts, cowboy_options \\ []) do
    run(:http, plug, opts, cowboy_options)
  end

  @doc """
  Runs cowboy under https.

  Besides the options described in the module documentation,
  this modules sets defaults and accepts all options defined
  in `Plug.SSL.configure/2`.

  ## Example

      # Starts a new interface
      Plug.Adapters.Cowboy.https MyPlug, [],
        port: 443,
        password: "SECRET",
        otp_app: :my_app,
        keyfile: "priv/ssl/key.pem",
        certfile: "priv/ssl/cert.pem",
        dhfile: "priv/ssl/dhparam.pem"

      # The interface above can be shutdown with
      Plug.Adapters.Cowboy.shutdown MyPlug.HTTPS

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

  @doc false
  # TODO: Deprecate this once we require Elixir v1.5+
  def child_spec(scheme, plug, opts, cowboy_options \\ []) do
    [ref, nb_acceptors, trans_opts, proto_opts] = args(scheme, plug, opts, cowboy_options)

    ranch_module =
      case scheme do
        :http -> :ranch_tcp
        :https -> :ranch_ssl
      end

    :ranch.child_spec(ref, nb_acceptors, ranch_module, trans_opts, :cowboy_protocol, proto_opts)
  end

  @doc """
  A function for starting a Cowboy server under Elixir v1.5 supervisors.

  It expects three options:

    * `:scheme` - either `:http` or `:https`
    * `:plug` - such as MyPlug or {MyPlug, plug_opts}
    * `:options` - the server options as specified in the module documentation

  ## Examples

  Assuming your Plug module is named `MyApp` you can add it to your
  supervision tree by using this function:

      children = [
        {Plug.Adapters.Cowboy, scheme: :http, plug: MyApp, options: [port: 4040]}
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

    {id, start, restart, shutdown, type, modules} =
      child_spec(scheme, plug, plug_opts, cowboy_opts)

    %{id: id, start: start, restart: restart, shutdown: shutdown, type: type, modules: modules}
  end

  ## Helpers

  @protocol_options [:timeout, :compress]

  defp run(scheme, plug, opts, cowboy_options) do
    case Application.ensure_all_started(:cowboy) do
      {:ok, _} ->
        verify_cowboy_version()

      {:error, {:cowboy, _}} ->
        raise "could not start the Cowboy application. Please ensure it is listed as a dependency in your mix.exs"
    end

    apply(:cowboy, :"start_#{scheme}", args(scheme, plug, opts, cowboy_options))
  end

  defp normalize_cowboy_options(cowboy_options, :http) do
    Keyword.put_new(cowboy_options, :port, 4000)
  end

  defp normalize_cowboy_options(cowboy_options, :https) do
    cowboy_options
    |> Keyword.put_new(:port, 4040)
    |> Plug.SSL.configure()
    |> case do
      {:ok, options} -> options
      {:error, message} -> fail(message)
    end
  end

  defp to_args(opts, non_keyword_opts) do
    opts = Keyword.delete(opts, :otp_app)
    {ref, opts} = Keyword.pop(opts, :ref)
    {dispatch, opts} = Keyword.pop(opts, :dispatch)
    {acceptors, opts} = Keyword.pop(opts, :acceptors, 100)
    {protocol_options, opts} = Keyword.pop(opts, :protocol_options, [])
    {log_request_errors, opts} = Keyword.pop(opts, :log_error_on_incomplete_requests, true)

    dispatch = :cowboy_router.compile(dispatch)
    {extra_options, transport_options} = Keyword.split(opts, @protocol_options)

    protocol_options =
      [env: [dispatch: dispatch]] ++
        add_on_response(log_request_errors, protocol_options) ++ extra_options

    [ref, acceptors, non_keyword_opts ++ transport_options, protocol_options]
  end

  defp add_on_response(log_request_errors, protocol_options) do
    {provided_onresponse, protocol_options} = Keyword.pop(protocol_options, :onresponse)
    add_on_response(log_request_errors, provided_onresponse, protocol_options)
  end

  defp add_on_response(false, nil, protocol_options) do
    protocol_options
  end

  defp add_on_response(false, fun, protocol_options) when is_function(fun) do
    [onresponse: fun] ++ protocol_options
  end

  defp add_on_response(false, {mod, fun}, protocol_options) when is_atom(mod) and is_atom(fun) do
    onresponse = fn status, headers, body, request ->
      apply(mod, fun, [status, headers, body, request])
    end

    [onresponse: onresponse] ++ protocol_options
  end

  defp add_on_response(true, nil, protocol_options) do
    [onresponse: &onresponse/4] ++ protocol_options
  end

  defp add_on_response(true, fun, protocol_options) when is_function(fun) do
    onresponse = fn status, headers, body, request ->
      onresponse(status, headers, body, request)
      fun.(status, headers, body, request)
    end

    [onresponse: onresponse] ++ protocol_options
  end

  defp add_on_response(true, {mod, fun}, protocol_options) when is_atom(mod) and is_atom(fun) do
    onresponse = fn status, headers, body, request ->
      onresponse(status, headers, body, request)
      apply(mod, fun, [status, headers, body, request])
    end

    [onresponse: onresponse] ++ protocol_options
  end

  defp onresponse(status, _headers, _body, request) do
    if status == 400 and empty_headers?(request) do
      Logger.error("""
      Cowboy returned 400 because it was unable to parse the request headers.

      This may happen because there are no headers, or there are too many headers
      or the header name or value are too large (such as a large cookie).

      You can customize those values when configuring your http/https
      server. The configuration option and default values are shown below:

          protocol_options: [
            max_header_name_length: 64,
            max_header_value_length: 4096,
            max_headers: 100,
            max_request_line_length: 8096
          ]
      """)
    end

    request
  end

  defp empty_headers?(request) do
    {headers, _} = :cowboy_req.headers(request)
    headers == []
  end

  defp build_ref(plug, scheme) do
    Module.concat(plug, scheme |> to_string |> String.upcase())
  end

  defp dispatch_for(plug, opts) do
    opts = plug.init(opts)
    [{:_, [{:_, Plug.Adapters.Cowboy.Handler, {plug, opts}}]}]
  end

  defp fail(message) do
    raise ArgumentError, "could not start Cowboy adapter, " <> message
  end

  defp verify_cowboy_version do
    case Application.spec(:cowboy, :vsn) do
      '1.' ++ _ ->
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
