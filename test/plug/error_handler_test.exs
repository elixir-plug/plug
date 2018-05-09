defmodule Plug.ErrorHandlerTest do
  use ExUnit.Case, async: true
  use Plug.Test

  defmodule Exception do
    defexception plug_status: 403, message: "oops"
  end

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
      send_resp(conn, 200, "oops")
      raise "oops"
    end

    get "/send_and_wrapped" do
      stack =
        try do
          raise "oops"
        rescue
          _ -> System.stacktrace()
        end

      raise Plug.Conn.WrapperError,
        conn: conn,
        kind: :error,
        stack: stack,
        reason: Exception.exception([])
    end
  end

  test "call/2 is overridden" do
    conn = conn(:get, "/boom")

    assert_raise RuntimeError, "oops", fn ->
      Router.call(conn, [])
    end

    assert_received {:plug_conn, :sent}
    assert {500, _headers, "Something went wrong"} = sent_resp(conn)
  end

  test "call/2 is overridden but is a no-op when response is already sent" do
    conn = conn(:get, "/send_and_boom")

    assert_raise RuntimeError, "oops", fn ->
      Router.call(conn, [])
    end

    assert_received {:plug_conn, :sent}
    assert {200, _headers, "oops"} = sent_resp(conn)
  end

  test "call/2 is overridden and does not unwrap wrapped errors" do
    conn = conn(:get, "/send_and_wrapped")

    assert_raise Plug.Conn.WrapperError, "** (Plug.ErrorHandlerTest.Exception) oops", fn ->
      Router.call(conn, [])
    end

    assert_received {:plug_conn, :sent}
    assert {403, _headers, "Something went wrong"} = sent_resp(conn)
  end
end
