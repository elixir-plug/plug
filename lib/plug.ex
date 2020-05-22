defmodule Plug do
  @moduledoc """
  The plug specification.

  There are two kind of plugs: function plugs and module plugs.

  #### Function plugs

  A function plug is any function that receives a connection and a set of
  options and returns a connection. Its type signature must be:

      (Plug.Conn.t, Plug.opts) :: Plug.Conn.t

  #### Module plugs

  A module plug is an extension of the function plug. It is a module that must
  export:

    * a `call/2` function with the signature defined above
    * an `init/1` function which takes a set of options and initializes it.

  The result returned by `init/1` is passed as second argument to `call/2`. Note
  that `init/1` may be called during compilation and as such it must not return
  pids, ports or values that are specific to the runtime.

  The API expected by a module plug is defined as a behaviour by the
  `Plug` module (this module).

  ## Examples

  Here's an example of a function plug:

      def json_header_plug(conn, opts) do
        Plug.Conn.put_resp_content_type(conn, "application/json")
      end

  Here's an example of a module plug:

      defmodule JSONHeaderPlug do
        import Plug.Conn

        def init(opts) do
          opts
        end

        def call(conn, _opts) do
          put_resp_content_type(conn, "application/json")
        end
      end

  ## The Plug pipeline

  The `Plug.Builder` module provides conveniences for building plug
  pipelines.
  """

  @type opts ::
          binary
          | tuple
          | atom
          | integer
          | float
          | [opts]
          | %{optional(opts) => opts}
          | MapSet.t()

  use Application

  @callback init(opts) :: opts
  @callback call(Plug.Conn.t(), opts) :: Plug.Conn.t()

  @doc false
  def start(_type, _args) do
    Plug.Supervisor.start_link()
  end

  @doc """
  Forwards requests to another Plug at a new path.

  The `path_info` on the forwarded connection will only include the trailing segments
  of the request path supplied to forward, while `conn.script_name` will
  retain the correct base path for e.g. url generation.

  ## Example

      defmodule Router do
        def init(opts), do: opts

        def call(conn, opts) do
          case conn do
            # Match subdomain
            %{host: "admin." <> _} ->
              AdminRouter.call(conn, opts)

            # Match path on localhost
            %{host: "localhost", path_info: ["admin" | rest]} ->
              Plug.forward(conn, rest, AdminRouter, opts)

            _ ->
              MainRouter.call(conn, opts)
          end
        end
      end

  """
  @spec forward(Plug.Conn.t(), [String.t()], atom, Plug.opts()) :: Plug.Conn.t()
  def forward(%Plug.Conn{path_info: path, script_name: script} = conn, new_path, target, opts) do
    {base, split_path} = Enum.split(path, length(path) - length(new_path))

    conn = do_forward(target, %{conn | path_info: split_path, script_name: script ++ base}, opts)
    %{conn | path_info: path, script_name: script}
  end

  defp do_forward({mod, fun}, conn, opts), do: apply(mod, fun, [conn, opts])
  defp do_forward(mod, conn, opts), do: mod.call(conn, opts)
end
