defmodule Plug.Builder do
  alias Plug.Conn

  @moduledoc """
  Conveniences for building plugs.

  This module can be used into a module in order to build
  a plug pipeline:

      defmodule MyApp do
        use Plug.Builder

        plug Plug.Logger
        plug :hello, upper: true

        def hello(conn, opts) do
          body = if opts[:upper], do: "WORLD", else: "world"
          send_resp(conn, 200, body)
        end
      end

  Multiple plugs can be defined with the `plug/2` macro, forming a
  pipeline. `Plug.Builder` also imports the `Plug.Conn` module, making
  functions like `send_resp/3` available.

  ## Plug behaviour

  Internally, `Plug.Builder` implements the `Plug` behaviour, which means
  both `init/1` and `call/2` functions are defined. By implementing the
  Plug API, `Plug.Builder` guarantees this module can be handed to a web
  server or used as part of another pipeline.

  ## Halting a Plug pipeline

  A Plug pipeline can be halted with `Plug.Conn.halt/1`. The builder will
  prevent further plugs downstream from being invoked and return the current
  connection.
  """

  @type plug :: module | atom

  @doc false
  defmacro __using__(_) do
    quote do
      @behaviour Plug

      def init(opts) do
        opts
      end

      def call(conn, opts) do
        plug_builder_call(conn, opts)
      end

      defoverridable [init: 1, call: 2]

      import Plug.Conn
      import Plug.Builder, only: [plug: 1, plug: 2]

      Module.register_attribute(__MODULE__, :plugs, accumulate: true)
      @before_compile Plug.Builder
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    plugs = Module.get_attribute(env.module, :plugs)

    if plugs == [] do
      raise "no plugs have been defined in #{inspect env.module}"
    end

    {conn, body} = Plug.Builder.compile(plugs)

    quote do
      defp plug_builder_call(unquote(conn), _), do: unquote(body)
    end
  end

  @doc """
  A macro that stores a new plug.
  """
  defmacro plug(plug, opts \\ []) do
    quote do
      @plugs {unquote(plug), unquote(opts), true}
    end
  end

  @doc """
  Compiles a plug pipeline.

  It expects a reversed pipeline (with the last plug coming first)
  and returns a tuple containing the reference to the connection
  as first argument and the compiled quote pipeline.
  """
  @spec compile([{plug, Plug.opts}]) :: {Macro.t, Macro.t}
  def compile(pipeline) do
    conn = quote do: conn
    {conn, Enum.reduce(pipeline, conn, &quote_plug(init_plug(&1), &2))}
  end

  defp init_plug({plug, opts, guard}) do
    case Atom.to_char_list(plug) do
      'Elixir.' ++ _ ->
        init_module_plug(plug, opts, guard)
      _ ->
        init_fun_plug(plug, opts, guard)
    end
  end

  defp init_module_plug(plug, opts, guard) do
    opts = plug.init(opts)

    if function_exported?(plug, :call, 2) do
      {:call, plug, opts, guard}
    else
      raise ArgumentError, message: "#{inspect plug} plug must implement call/2"
    end
  end

  defp init_fun_plug(plug, opts, guard) do
    {:fun, plug, opts, guard}
  end

  defp quote_plug({:call, plug, opts, guard}, acc) do
    call = quote do: unquote(plug).call(conn, unquote(Macro.escape(opts)))

    quote do
      case unquote(compile_guard(call, guard)) do
        %Conn{halted: true} = conn -> conn
        %Conn{} = conn             -> unquote(acc)
        _ -> raise "expected #{unquote(inspect plug)}.call/2 to return a Plug.Conn"
      end
    end
  end

  defp quote_plug({:fun, plug, opts, guard}, acc) do
    call = quote do: unquote(plug)(conn, unquote(Macro.escape(opts)))

    quote do
      case unquote(compile_guard(call, guard)) do
        %Conn{halted: true} = conn -> conn
        %Conn{} = conn             -> unquote(acc)
        _ -> raise "expected #{unquote(plug)}/2 to return a Plug.Conn"
      end
    end
  end

  defp compile_guard(call, true) do
    call
  end

  defp compile_guard(call, guard) do
    quote do
      case true do
        true when unquote(guard) -> unquote(call)
        true -> conn
      end
    end
  end
end
