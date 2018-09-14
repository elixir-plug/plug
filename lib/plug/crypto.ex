defmodule Plug.Crypto do
  @moduledoc """
  Namespace and module for Crypto functionality.

  Please see `Plug.Crypto.KeyGenerator`, `Plug.Crypto.MessageEncryptor`,
  and `Plug.Crypto.MessageVerifier` for more functionality.
  """

  use Bitwise

  @doc """
  Prunes the stacktrace to remove any argument trace.
  """
  def prune_args_from_stacktrace([{mod, fun, [_ | _] = args, info} | rest]),
    do: [{mod, fun, length(args), info} | rest]

  def prune_args_from_stacktrace(stack) when is_list(stack),
    do: stack

  @doc """
  A restricted version of `:erlang.binary_to_term/2` that
  forbids possibly unsafe terms.
  """
  def safe_binary_to_term(binary, opts \\ []) when is_binary(binary) do
    term = :erlang.binary_to_term(binary, opts)
    safe_terms(term)
    term
  end

  defp safe_terms(list) when is_list(list) do
    safe_list(list)
  end

  defp safe_terms(tuple) when is_tuple(tuple) do
    safe_tuple(tuple, tuple_size(tuple))
  end

  defp safe_terms(map) when is_map(map) do
    folder = fn key, value, acc ->
      safe_terms(key)
      safe_terms(value)
      acc
    end

    :maps.fold(folder, map, map)
  end

  defp safe_terms(other)
       when is_atom(other) or is_number(other) or is_bitstring(other) or is_pid(other) or
              is_reference(other) do
    other
  end

  defp safe_terms(other) do
    raise ArgumentError,
          "cannot deserialize #{inspect(other)}, the term is not safe for deserialization"
  end

  defp safe_list([]), do: :ok

  defp safe_list([h | t]) when is_list(t) do
    safe_terms(h)
    safe_list(t)
  end

  defp safe_list([h | t]) do
    safe_terms(h)
    safe_terms(t)
  end

  defp safe_tuple(_tuple, 0), do: :ok

  defp safe_tuple(tuple, n) do
    safe_terms(:erlang.element(n, tuple))
    safe_tuple(tuple, n - 1)
  end

  @doc """
  Masks the token on the left with the token on the right.

  Both tokens are required to have the same size.
  """
  def mask(left, right) do
    mask(left, right, "")
  end

  defp mask(<<x, left::binary>>, <<y, right::binary>>, acc) do
    mask(left, right, <<acc::binary, x ^^^ y>>)
  end

  defp mask(<<>>, <<>>, acc) do
    acc
  end

  @doc """
  Compares the two binaries (one being masked) in constant-time to avoid
  timing attacks.

  It is assumed the right token is masked according to the given mask.
  """
  @spec masked_compare(binary(), binary(), binary()) :: boolean()
  def masked_compare(left, right, mask)
      when is_binary(left) and is_binary(right) and is_binary(mask) do
    byte_size(left) == byte_size(right) and masked_compare(left, right, mask, 0)
  end

  defp masked_compare(<<x, left::binary>>, <<y, right::binary>>, <<z, mask::binary>>, acc) do
    xorred = x ^^^ (y ^^^ z)
    masked_compare(left, right, mask, acc ||| xorred)
  end

  defp masked_compare(<<>>, <<>>, <<>>, acc) do
    acc === 0
  end

  @doc """
  Compares the two binaries in constant-time to avoid timing attacks.

  See: http://codahale.com/a-lesson-in-timing-attacks/
  """
  @spec secure_compare(binary(), binary()) :: boolean()
  def secure_compare(left, right) when is_binary(left) and is_binary(right) do
    byte_size(left) == byte_size(right) and secure_compare(left, right, 0)
  end

  defp secure_compare(<<x, left::binary>>, <<y, right::binary>>, acc) do
    xorred = x ^^^ y
    secure_compare(left, right, acc ||| xorred)
  end

  defp secure_compare(<<>>, <<>>, acc) do
    acc === 0
  end
end
