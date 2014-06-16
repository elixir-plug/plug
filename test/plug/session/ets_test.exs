defmodule Plug.Session.ETSTest do
  use ExUnit.Case
  alias Plug.Session.ETS

  @ets_table :plug_session_test

  setup do
    :ets.new(@ets_table, [:named_table])
    :ok
  end

  test "put and get session" do
    opts = ETS.init([table: @ets_table])

    assert "foo" = ETS.put("foo", :foo, opts)
    assert "bar" = ETS.put("bar", :bar, opts)

    assert {"foo", :foo} = ETS.get("foo", opts)
    assert {"bar", :bar} = ETS.get("bar", opts)
    assert {nil, nil} = ETS.get("unknown", opts)
  end

  test "delete session" do
    opts = ETS.init([table: @ets_table])

    ETS.put("foo", :foo, opts)
    ETS.put("bar", :bar, opts)
    ETS.delete("foo", opts)

    assert {nil, nil} = ETS.get("foo", opts)
    assert {"bar", :bar} = ETS.get("bar", opts)
  end

  test "generate new sid" do
    opts = ETS.init([table: @ets_table])
    sid = ETS.put(nil, :foo, opts)
    assert byte_size(sid) == 128
  end

  test "invalidate sid if unknown" do
    opts = ETS.init([table: @ets_table])
    assert {nil, nil} = ETS.get("unknown_sid", opts)
  end
end
