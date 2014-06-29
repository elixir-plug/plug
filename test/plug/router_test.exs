defmodule Plug.RouterTest do
  defmodule Sample do
    defmodule Forward do
      use Plug.Router
      import Plug.Conn

      plug :match
      plug :dispatch

      get "/foo" do
        conn |> resp(200, "forwarded")
      end

      get "/script_name" do
        conn |> resp(200, Enum.join(conn.script_name, ","))
      end
    end

    use Plug.Router
    import Plug.Conn

    plug :match
    plug :dispatch

    get "/" do
      conn |> resp(200, "root")
    end

    get "/1/bar" do
      conn |> resp(200, "ok")
    end

    get "/2/:bar" do
      conn |> resp(200, inspect(bar))
    end

    get "/3/bar-:bar" do
      conn |> resp(200, inspect(bar))
    end

    get "/4/*bar" do
      conn |> resp(200, inspect(bar))
    end

    get "/5/bar-*bar" do
      conn |> resp(200, inspect(bar))
    end

    get ["6", "bar"] do
      conn |> resp(200, "ok")
    end

    get "/7/:bar" when byte_size(bar) <= 3 do
      conn |> resp(200, inspect(bar))
    end

    forward "/forward", to: Forward
    forward "/nested/forward", to: Forward

    match ["8", "bar"] do
      conn |> resp(200, "ok")
    end

    match _ do
      conn |> resp(404, "oops")
    end
  end

  use ExUnit.Case, async: true
  use Plug.Test

  test "dispatch root" do
    conn = call(Sample, conn(:get, "/"))
    assert conn.resp_body == "root"
  end

  test "dispatch literal segment" do
    conn = call(Sample, conn(:get, "/1/bar"))
    assert conn.resp_body == "ok"
  end

  test "dispatch dynamic segment" do
    conn = call(Sample, conn(:get, "/2/value"))
    assert conn.resp_body == ~s("value")
  end

  test "dispatch dynamic segment with prefix" do
    conn = call(Sample, conn(:get, "/3/bar-value"))
    assert conn.resp_body == ~s("value")
  end

  test "dispatch glob segment" do
    conn = call(Sample, conn(:get, "/4/value"))
    assert conn.resp_body == ~s(["value"])

    conn = call(Sample, conn(:get, "/4/value/extra"))
    assert conn.resp_body == ~s(["value", "extra"])
  end

  test "dispatch glob segment with prefix" do
    conn = call(Sample, conn(:get, "/5/bar-value/extra"))
    assert conn.resp_body == ~s(["bar-value", "extra"])
  end

  test "dispatch custom route" do
    conn = call(Sample, conn(:get, "/6/bar"))
    assert conn.resp_body == "ok"
  end

  test "dispatch with guards" do
    conn = call(Sample, conn(:get, "/7/a"))
    assert conn.resp_body == ~s("a")

    conn = call(Sample, conn(:get, "/7/ab"))
    assert conn.resp_body == ~s("ab")

    conn = call(Sample, conn(:get, "/7/abc"))
    assert conn.resp_body == ~s("abc")

    conn = call(Sample, conn(:get, "/7/abcd"))
    assert conn.resp_body == "oops"
  end

  test "dispatch wrong verb" do
    conn = call(Sample, conn(:post, "/1/bar"))
    assert conn.resp_body == "oops"
  end

  test "dispatch with forwarding" do
    conn = call(Sample, conn(:get, "/forward/foo"))
    assert conn.resp_body == "forwarded"
    assert conn.path_info == ["forward", "foo"]
  end

  test "dispatch with forwarding including slashes" do
    conn = call(Sample, conn(:get, "/nested/forward/foo"))
    assert conn.resp_body == "forwarded"
    assert conn.path_info == ["nested", "forward", "foo"]
  end

  test "forwarding modifies script_name" do
    conn = call(Sample, conn(:get, "/nested/forward/script_name"))
    assert conn.resp_body == "nested,forward"
  end

  test "dispatch any verb" do
    conn = call(Sample, conn(:get, "/8/bar"))
    assert conn.resp_body == "ok"

    conn = call(Sample, conn(:post, "/8/bar"))
    assert conn.resp_body == "ok"

    conn = call(Sample, conn(:put, "/8/bar"))
    assert conn.resp_body == "ok"

    conn = call(Sample, conn(:patch, "/8/bar"))
    assert conn.resp_body == "ok"

    conn = call(Sample, conn(:delete, "/8/bar"))
    assert conn.resp_body == "ok"

    conn = call(Sample, conn(:options, "/8/bar"))
    assert conn.resp_body == "ok"

    conn = call(Sample, conn(:unknown, "/8/bar"))
    assert conn.resp_body == "ok"
  end

  test "dispatch not found" do
    conn = call(Sample, conn(:get, "/unknown"))
    assert conn.status == 404
    assert conn.resp_body == "oops"
  end

  defp call(mod, conn) do
    mod.call(conn, [])
  end
end
