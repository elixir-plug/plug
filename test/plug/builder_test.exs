defmodule Plug.BuilderTest do
  import Plug.Conn

  defmodule Wrapper do
    def init(val) do
      {:init, val}
    end

    def wrap(conn, opts, fun) do
      stack = [{:wrap, opts}|conn.assigns[:stack]]
      fun.(assign(conn, :stack, stack))
    end
  end

  defmodule Module do
    def init(val) do
      {:init, val}
    end

    def call(conn, opts) do
      stack = [{:call, opts}|conn.assigns[:stack]]
      assign(conn, :stack, stack)
    end
  end

  defmodule Sample do
    use Plug.Builder

    plug :fun
    plug Wrapper, ~r"opts"
    plug Module, :opts

    def fun(conn, opts) do
      stack = [{:fun, opts}|conn.assigns[:stack]]
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
      throw {:not_found, conn}
    end
  end

  use ExUnit.Case, async: true
  use Plug.Test

  test "exports the init/1 function" do
    assert Sample.init(:ok) == :ok
  end

  test "builds plug stack in the order" do
    conn = conn(:get, "/") |> assign(:stack, [])
    assert Sample.call(conn, []).assigns[:stack] ==
           [call: {:init, :opts}, wrap: {:init, ~r"opts"}, fun: []]
  end

  test "allows call/2 to be overridden with super" do
    conn = conn(:get, "/") |> Overridable.call([])
    assert conn.assigns[:not_found] == :caught
    assert conn.assigns[:entered_stack] == true
  end
end
