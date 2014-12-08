defmodule Plug.ErrorHandlerTest do
  use ExUnit.Case, async: true
  use Plug.Test

  defmodule Router do
    use Plug.Router
    use Plug.ErrorHandler

    plug :match
    plug :dispatch

    def call(conn, opts) do
      if conn.path_info == ~w(boom) do
        raise "oops"
      else
        super(conn, opts)
      end
    end

    get "/send_and_boom" do
      send_resp conn, 200, "oops"
      raise "oops"
    end
  end

  test "call/2 is overridden" do
    assert_raise RuntimeError, "oops", fn ->
      conn(:get, "/boom") |> Router.call([])
    end

    assert_received {:plug_conn, :sent}
  end

  test "call/2 is overridden but is a no-op when response is already sent" do
    assert_raise RuntimeError, "oops", fn ->
      conn(:get, "/send_and_boom") |> Router.call([])
    end

    assert_received {:plug_conn, :sent}
  end
end
