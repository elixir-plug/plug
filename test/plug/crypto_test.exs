defmodule Plug.CryptoTest do
  use ExUnit.Case, async: true

  import Plug.Crypto

  test "prunes stacktrace" do
    assert prune_args_from_stacktrace([{:erlang, :+, 2, []}]) == [{:erlang, :+, 2, []}]
    assert prune_args_from_stacktrace([{:erlang, :+, [1, 2], []}]) == [{:erlang, :+, 2, []}]
  end

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

  test "safe_binary_to_term" do
    value = %{1 => {:foo, ["bar", 2.0, %URI{}, [self() | make_ref()], <<0::4>>]}}
    assert safe_binary_to_term(:erlang.term_to_binary(value)) == value

    assert_raise ArgumentError, fn ->
      safe_binary_to_term(:erlang.term_to_binary(%{1 => {:foo, [fn -> :bar end]}}))
    end

    assert_raise ArgumentError, fn ->
      safe_binary_to_term(<<131, 100, 0, 7, 103, 114, 105, 102, 102, 105, 110>>, [:safe])
    end
  end
end
