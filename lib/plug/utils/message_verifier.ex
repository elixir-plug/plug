defmodule Plug.Utils.MessageVerifier do
  @moduledoc """
  `MessageVerifier` makes it easy to generate and verify messages
  which are signed to prevent tampering.

  For example, the cookie store uses this verifier to send data
  to the client. Although the data can be read by the client, he
  cannot tamper it.
  """

  use Bitwise
  import Plug.Serializer

  @doc """
  Decodes and verifies the encoded binary was not tampared with.
  """
  def verify(secret, encoded, serializer \\ :elixir) do
    
    case String.split(encoded, "--") do
      [content, digest] when content != "" and digest != "" ->
        if secure_compare(digest(secret, content), digest) do
          { :ok, content |> Base.decode64! |> convert_serializer(serializer).decode}
        else
          :error
        end
      _ ->
        :error
    end
  end

  @doc """
  Generates an encoded and signed binary for the given term.
  """
  def generate(secret, term, serializer \\ :elixir) do
    encoded = term |> convert_serializer(serializer).encode |> Base.encode64
    encoded <> "--" <> digest(secret, encoded)
  end

  defp digest(secret, data) do
    :crypto.hmac(:sha, secret, data) |> Base.encode64
  end

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
