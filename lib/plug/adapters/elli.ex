defmodule Plug.Adapters.Elli do
  @moduledoc """
  Adapter interface to the Elli webserver

  ## Options

  * `:ip` - the ip to bind the server to.
            Must be a tuple in the format `{ x, y, z, w }`.

  * `:port` - the port to run the server.
              Defaults to 4000 (http) and 4040 (https).

  * `:min_acceptors` - the minimum number of acceptors for the listener.
                       Defaults to 20.

  * `:max_body_size` - The maximum allowed body size in bytes of a
                       request. Defaults to 10MB.

  * `:ref` - the reference name to be used. Defaults to `plug.HTTP`.
             This is the value that needs to be given on shutdown.

  """

  alias Plug.Adapters.Elli.Supervisor

  @doc """
  Runs Elli under http.

  ## Example

      # Starts a new interface
      Plug.Adapters.Elli.http MyPlug, [], port: 80

      # The interface above can be shutdown with
      Plug.Adapters.Elli.shutdown MyPlug.HTTP

  """
  def http(plug, opts, options // []) do
    case Supervisor.start_link do
      { :ok, _pid } ->
        start_elli(plug, opts, options)
      { :error, { :already_started, _pid } } ->
        start_elli(plug, opts, options)
      error ->
        error
    end
  end

  @doc """
  Shutdowns the given reference. If you have a plug `MyPlug`,
  the default reference is `MyPlug.HTTP`.
  """
  def shutdown(ref) do
    Supervisor.stop_elli(ref)
  end

  defp start_elli(plug, opts, options) do
      ref = Module.concat(plug, HTTP)
      handler = [callback: Plug.Adapters.Elli.Handler,
                 callback_args: { plug, opts }]
      options = Keyword.put_new(options, :port, 4000)
                |> Keyword.merge(handler)
      Supervisor.start_elli(ref, options)
  end
end