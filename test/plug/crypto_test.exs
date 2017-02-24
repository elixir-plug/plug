defmodule Plug.CryptoTest do
  use ExUnit.Case, async: true

  import Plug.Crypto

  test "masks tokens" do
    assert mask(<<0, 1, 0, 1>>, <<0, 1, 1, 0>>) == <<0, 0, 1, 1>>
    assert mask(<<0, 0, 1, 1>>, <<0, 1, 1, 0>>) == <<0, 1, 0, 1>>
  end

  test "compares binaries securely" do
    assert secure_compare(<<>>, <<>>)
    assert secure_compare(<<0>>, <<0>>)

    refute secure_compare(<<>>, <<1>>)
    refute secure_compare(<<1>>, <<>>)
    refute secure_compare(<<0>>, <<1>>)
  end

  test "compares masked binaries securely" do
    assert masked_compare(<<>>, <<>>, <<>>)
    assert masked_compare(<<0>>, <<0>>, <<0>>)
    assert masked_compare(<<0, 1, 0, 1>>, <<0, 0, 1, 1>>, <<0, 1, 1, 0>>)

    refute masked_compare(<<>>, <<1>>, <<0>>)
    refute masked_compare(<<1>>, <<>>, <<0>>)
    refute masked_compare(<<0>>, <<1>>, <<0>>)
  end
end
