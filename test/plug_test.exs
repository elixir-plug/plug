defmodule PlugTest do
  use ExUnit.Case, async: true
  use Plug.Test

  import ExUnit.CaptureLog

  defmodule Response do
    use Plug.Router

    plug :match
    plug :dispatch

    get "/*path" do
      response = """
      path: #{path}
      script_name: #{Path.join(conn.script_name)}
      path_info: #{Path.join(conn.path_info)}
      """

      resp(conn, 200, response)
    end
  end

  defmodule Forward do
    def init(opts) do
      Forward.init(opts)
    end

    def call(conn, opts) do
      case conn do
        %{path_info: ["prefix" | rest]} ->
          Plug.forward(conn, rest, Response, opts)

        _ ->
          Response.call(conn, opts)
      end
    end
  end

  describe "forward" do
    test "strips segments of the path affecting path matching for the called plug" do
      conn = Forward.call(conn(:get, "/prefix/more/segments"), [])
      assert conn.resp_body =~ "script_name: prefix"
      assert conn.resp_body =~ "path_info: more/segments"
    end
  end

  defmodule Halter do
    def init(:opts), do: :inited
    def call(conn, :inited), do: %{conn | halted: true}
  end

  defmodule NotPlug do
    def init(:opts), do: :inited
    def call(_conn, :inited), do: %{}
  end

  describe "run" do
    test "invokes plugs" do
      conn = Plug.run(conn(:head, "/"), [{Plug.Head, []}])
      assert conn.method == "GET"

      conn = Plug.run(conn(:head, "/"), [{Plug.Head, []}, &send_resp(&1, 200, "ok")])
      assert conn.method == "GET"
      assert conn.status == 200
    end

    test "does not invoke plugs if halted" do
      conn = Plug.run(%{conn(:get, "/") | halted: true}, [&raise(inspect(&1))])
      assert conn.halted
    end

    test "aborts if plug halts" do
      conn = Plug.run(conn(:get, "/"), [&%{&1 | halted: true}, &raise(inspect(&1))])
      assert conn.halted
    end

    test "logs when halting" do
      assert capture_log(fn ->
               assert Plug.run(conn(:get, "/"), [{Halter, :opts}], log_on_halt: :error).halted
             end) =~ "[error] Plug halted in PlugTest.Halter.call/2"

      halter = &%{&1 | halted: true}

      assert capture_log(fn ->
               assert Plug.run(conn(:get, "/"), [halter], log_on_halt: :error).halted
             end) =~ "[error] Plug halted in #{inspect(halter)}"
    end

    test "raise exception with invalid return" do
      msg = "expected PlugTest.NotPlug to return Plug.Conn, got: %{}"

      assert_raise RuntimeError, msg, fn ->
        Plug.run(conn(:get, "/"), [{NotPlug, :opts}])
      end

      not_plug = fn _ -> %{} end
      msg = ~r/expected #Function.* to return Plug.Conn, got: %{}/

      assert_raise RuntimeError, msg, fn ->
        Plug.run(conn(:get, "/"), [not_plug])
      end
    end
  end
end
