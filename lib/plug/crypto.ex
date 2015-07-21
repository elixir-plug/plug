defmodule Plug.Crypto do
  @moduledoc """
  Namespace and module for crypto functionality.
  """

  use Bitwise

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
  def masked_compare(left, right, mask) do
    if byte_size(left) == byte_size(right) do
      masked_compare(left, right, mask, 0) == 0
    else
      false
    end
  end

  defp masked_compare(<<x, left::binary>>, <<y, right::binary>>, <<z, mask::binary>>, acc) do
    masked_compare(left, right, mask, acc ||| (x ^^^ (y ^^^ z)))
  end

  defp masked_compare(<<>>, <<>>, <<>>, acc) do
    acc
  end

  @doc """
  Compares the two binaries in constant-time to avoid timing attacks.

  See: http://codahale.com/a-lesson-in-timing-attacks/
  """
  def secure_compare(left, right) do
    if byte_size(left) == byte_size(right) do
      secure_compare(left, right, 0) == 0
    else
      false
    end
  end

  defp secure_compare(<<x, left :: binary>>, <<y, right :: binary>>, acc) do
    secure_compare(left, right, acc ||| (x ^^^ y))
  end

  defp secure_compare(<<>>, <<>>, acc) do
    acc
  end
end
