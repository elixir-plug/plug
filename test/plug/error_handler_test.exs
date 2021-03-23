defmodule Plug.ErrorHandlerTest do
  use ExUnit.Case, async: true
  use Plug.Test

  defmodule ForbiddenError do
    defexception plug_status: 403, message: "oops"
  end

  defmodule NotFoundError do
    defexception plug_status: :not_found, message: "oops"
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
          _ -> __STACKTRACE__
        end

      raise Plug.Conn.WrapperError,
        conn: conn,
        kind: :error,
        stack: stack,
        reason: ForbiddenError.exception([])
    end

    get "/status_as_atom" do
      raise NotFoundError
      send_resp(conn, 200, "ok")
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

    assert_raise Plug.Conn.WrapperError, "** (RuntimeError) oops", fn ->
      Router.call(conn, [])
    end

    assert_received {:plug_conn, :sent}
    assert {200, _headers, "oops"} = sent_resp(conn)
  end

  test "call/2 is overridden and does not unwrap wrapped errors" do
    conn = conn(:get, "/send_and_wrapped")

    assert_raise Plug.Conn.WrapperError, "** (Plug.ErrorHandlerTest.ForbiddenError) oops", fn ->
      Router.call(conn, [])
    end

    assert_received {:plug_conn, :sent}
    assert {403, _headers, "Something went wrong"} = sent_resp(conn)
  end

  test "call/2 supports statuses as atoms" do
    conn = conn(:get, "/status_as_atom")

    assert_raise Plug.Conn.WrapperError, "** (Plug.ErrorHandlerTest.NotFoundError) oops", fn ->
      Router.call(conn, [])
    end

    assert_received {:plug_conn, :sent}
    assert {404, _headers, "Something went wrong"} = sent_resp(conn)
  end

  test "define a behaviour with a default implementation" do
    assert ExUnit.CaptureIO.capture_io(:stderr, fn ->
             Code.eval_string("""
             defmodule Plug.ErrorHandlerTest.BadImplRouter do
               use Plug.Router
               use Plug.ErrorHandler

               plug :match
               plug :dispatch

               match _, do: conn

               @impl Plug.ErrorHandler
               def handle_errors(_conn), do: :boom
             end
             """)
           end) =~
             "got \"@impl Plug.ErrorHandler\" for function handle_errors/1 but this behaviour does not specify such callback."
  end
end
