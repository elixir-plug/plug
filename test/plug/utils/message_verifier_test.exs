defmodule Plug.Utils.MessageVerifierTest do
  use ExUnit.Case, async: true

  alias Plug.Utils.MessageVerifier, as: MV

  test "generates a signed message" do
    [content, encoded] = String.split MV.sign("secret", "hello world"), "--"
    assert content |> Base.decode64 == {:ok, "hello world"}
    assert byte_size(encoded) == 28
  end

  test "verifies a signed message" do
    signed = MV.sign("secret", "hello world")
    assert MV.verify("secret", signed) == {:ok, "hello world"}
  end

  test "does not verify a signed message if secret changed" do
    signed = MV.sign("secret", "hello world")
    assert MV.verify("secreto", signed) == :error
  end

  test "does not verify a tampered message" do
    [_, encoded] = String.split MV.sign("secret", "hello world"), "--"
    content = "another world" |> Base.encode64
    assert MV.verify("secret", content <> "--" <> encoded) == :error
  end
end
