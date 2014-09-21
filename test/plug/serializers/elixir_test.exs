defmodule Plug.Serializers.ElixirTest do
  use ExUnit.Case, async: true

  alias Plug.Serializers.ELIXIR

  test "it encodes values" do
    term = %{foo: "bar"}
    encoded = "837400000001640003666F6F6D00000003626172"
    assert  encoded == ELIXIR.encode(term) |> Base.encode16
  end

  test "it decodes values" do
    encoded = "837400000001640003666F6F6D00000003626172"
    assert  ELIXIR.decode(encoded |> Base.decode16!).foo == "bar"
  end
end
