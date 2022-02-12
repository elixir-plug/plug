defmodule Plug.BuilderTest do
  defmodule Module do
    import Plug.Conn

    def init(val) do
      {:init, val}
    end

    def call(conn, opts) do
      stack = [{:call, opts} | conn.assigns[:stack]]
      assign(conn, :stack, stack)
    end
  end

  defmodule Sample do
    use Plug.Builder, copy_opts_to_assign: :stack

    plug :fun, :step1
    plug Module, :step2
    plug Module, :step3

    def fun(conn, opts) do
      stack = [{:fun, opts} | conn.assigns[:stack]]
      assign(conn, :stack, stack)
    end
  end

  defmodule Overridable do
    use Plug.Builder

    def call(conn, opts) do
      try do
        super(conn, opts)
      catch
        :throw, {:not_found, conn} -> assign(conn, :not_found, :caught)
      end
    end

    plug :boom

    def boom(conn, _opts) do
      conn = assign(conn, :entered_stack, true)
      throw({:not_found, conn})
    end
  end

  defmodule Halter do
    use Plug.Builder

    plug :step, :first
    plug :step, :second
    plug :authorize
    plug :step, :end_of_chain_reached

    def step(conn, step), do: assign(conn, step, true)

    def authorize(conn, _) do
      conn
      |> assign(:authorize_reached, true)
      |> halt
    end
  end

  defmodule FaultyModulePlug do
    defmodule FaultyPlug do
      def init([]), do: []

      # Doesn't return a Plug.Conn
      def call(_conn, _opts), do: "foo"
    end

    use Plug.Builder
    plug FaultyPlug
  end

  defmodule FaultyFunctionPlug do
    use Plug.Builder
    plug :faulty_function

    # Doesn't return a Plug.Conn
    def faulty_function(_conn, _opts), do: "foo"
  end

  use ExUnit.Case, async: true
  use Plug.Test

  test "exports the init/1 function" do
    assert Sample.init(:ok) == :ok
  end

  test "builds plug stack in the order" do
    conn = conn(:get, "/")

    assert Sample.call(conn, []).assigns[:stack] == [
             call: {:init, :step3},
             call: {:init, :step2},
             fun: :step1
           ]

    assert Sample.call(conn, [:initial]).assigns[:stack] == [
             {:call, {:init, :step3}},
             {:call, {:init, :step2}},
             {:fun, :step1},
             :initial
           ]
  end

  test "allows call/2 to be overridden with super" do
    conn = Overridable.call(conn(:get, "/"), [])
    assert conn.assigns[:not_found] == :caught
    assert conn.assigns[:entered_stack] == true
  end

  test "halt/2 halts the plug stack" do
    conn = Halter.call(conn(:get, "/"), [])
    assert conn.halted
    assert conn.assigns[:first]
    assert conn.assigns[:second]
    assert conn.assigns[:authorize_reached]
    refute conn.assigns[:end_of_chain_reached]
  end

  test "an exception is raised if a plug doesn't return a connection" do
    assert_raise RuntimeError, fn ->
      FaultyModulePlug.call(conn(:get, "/"), [])
    end

    assert_raise RuntimeError, fn ->
      FaultyFunctionPlug.call(conn(:get, "/"), [])
    end
  end

  test "an exception is raised at compile time if a plug with no call/2 function is plugged" do
    assert_raise ArgumentError, fn ->
      defmodule BadPlug do
        defmodule Bad do
          def init(opts), do: opts
        end

        use Plug.Builder
        plug Bad
      end
    end
  end

  test "compile and runtime init modes" do
    {:ok, _agent} = Agent.start_link(fn -> :compile end, name: :plug_init)

    defmodule Assigner do
      use Plug.Builder

      def init(agent), do: {:init, Agent.get(agent, & &1)}
      def call(conn, opts), do: Plug.Conn.assign(conn, :opts, opts)
    end

    defmodule CompileInit do
      use Plug.Builder

      var = :plug_init
      plug Assigner, var
    end

    defmodule RuntimeInit do
      use Plug.Builder, init_mode: :runtime

      var = :plug_init
      plug Assigner, var
    end

    :ok = Agent.update(:plug_init, fn :compile -> :runtime end)

    assert CompileInit.call(%Plug.Conn{}, :plug_init).assigns.opts == {:init, :compile}
    assert RuntimeInit.call(%Plug.Conn{}, :plug_init).assigns.opts == {:init, :runtime}
  end
end
