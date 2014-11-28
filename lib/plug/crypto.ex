defmodule Plug.Crypto do
  @moduledoc """
  Namespace and module for cyrpto functionality.
  """

  use Bitwise

  @doc """
  Compares the two binaries in constant-time to avoid timing attacks.

  See: http://codahale.com/a-lesson-in-timing-attacks/
  """
  def secure_compare(left, right) do
    if byte_size(left) == byte_size(right) do
      arithmetic_compare(left, right, 0) == 0
    else
      false
    end
  end

  defp arithmetic_compare(<<x, left :: binary>>, <<y, right :: binary>>, acc) do
    arithmetic_compare(left, right, acc ||| (x ^^^ y))
  end

  defp arithmetic_compare(<<>>, <<>>, acc) do
    acc
  end
end
