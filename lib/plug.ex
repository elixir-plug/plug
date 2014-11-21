defmodule Plug do
  @moduledoc """
  The plug specification.

  There are two kind of plugs: function plugs and module plugs. A
  function plug is any function that receives a connection and a
  set of options and returns a connection. Its type signature must be:

      (Plug.Conn.t, Plug.opts) :: Plug.Conn.t

  A module plug is an extension of the function plug. It must export a
  `call/2` function, with the signature defined above, but it must also
  provide an `init/1` function, for initialization of the options.

  The result returned by `init/1` is the one given as second argument to
  `call/2`. Note `init/1` may be called during compilation and as such
  it must not return pids, ports or values that are not specific to the
  runtime.

  The API expected by a module plug is defined as a behaviour by the
  `Plug` module (this module).

  ## The Plug pipeline

  The `Plug.Builder` module provides conveniences for building plug
  pipelines.
  """

  @type opts :: tuple | atom | integer | float | [opts]

  use Behaviour
  use Application

  defcallback init(opts) :: opts
  defcallback call(Plug.Conn.t, opts) :: Plug.Conn.t

  @doc false
  def start(_type, _args) do
    Logger.add_translator {Plug.Adapters.Translator, :translate}
    Plug.Supervisor.start_link()
  end
end
