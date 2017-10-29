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
      send_resp conn, 200, "oops"
      raise "oops"
    end

    get "/send_undef" do
      _ = conn
      String.nonexistant_function
    end

    get "/send_and_wrapped" do
      raise Plug.Conn.WrapperError, conn: conn,
        kind: :error, stack: System.stacktrace,
        reason: Exception.exception([])
    end

    def handle_errors(conn, error) do
      send(self(), {:handle_error, conn, error})
      send_resp(conn, conn.status, "Something went wrong")
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

  test "call/2 normalizes the error" do
    conn = conn(:get, "/send_undef")

    expected_error = %UndefinedFunctionError{arity: 0, exports: nil,
                      function: :nonexistant_function, module: String, reason: nil}

    assert catch_error(Router.call(conn, [])) ==  expected_error


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

  test "call/2 sends unwrapped errors to handle_errors" do
    conn = conn(:get, "/send_and_wrapped")

    assert_raise Plug.Conn.WrapperError, "** (Plug.ErrorHandlerTest.Exception) oops", fn ->
      Router.call(conn, [])
    end

    {_, _, %{reason: handle_errors_reason}} = assert_received {:handle_error, _, _}
    expected_error =  %Plug.ErrorHandlerTest.Exception{message: "oops", plug_status: 403}
    assert handle_errors_reason == expected_error
    assert_received {:plug_conn, :sent}
    assert {403, _headers, "Something went wrong"} = sent_resp(conn)
  end
end
