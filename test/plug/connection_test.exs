defmodule Plug.ConnectionTest do
  use ExUnit.Case, async: true

  alias  Plug.Conn
  import Plug.Connection

  test "assign/3" do
    conn = Conn[]
    assert conn.assigns[:hello] == nil
    conn = assign(conn, :hello, :world)
    assert conn.assigns[:hello] == :world 
  end
end
