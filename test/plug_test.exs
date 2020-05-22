defmodule PlugTest do
  use ExUnit.Case, async: true
  use Plug.Test

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

  test "forward can strip segments of the path affecting path matching for the called plug" do
    conn = Forward.call(conn(:get, "/prefix/more/segments"), [])
    assert conn.resp_body =~ "script_name: prefix"
    assert conn.resp_body =~ "path_info: more/segments"
  end
end
