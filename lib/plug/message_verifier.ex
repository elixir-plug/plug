defmodule Plug.MessageVerifier do
  @moduledoc """
  `MessageVerifier` makes it easy to generate and verify messages
  which are signed to prevent tampering.

  For example, the cookie store uses this verifier to send data
  to the client. Although the data can be read by the client, he
  cannot tamper it.
  """

  @doc """
  Decodes and verifies the encoded binary was not tampared with.
  """
  def verify(secret, encoded) do
    case String.split(encoded, "--") do
      [content, digest] when content != "" and digest != "" ->
        if secure_compare(digest(secret, content), digest) do
          { :ok, content |> Base.decode64! |> :erlang.binary_to_term }
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
  def generate(secret, term) do
    encoded = term |> :erlang.term_to_binary |> Base.encode64
    encoded <> "--" <> digest(secret, encoded)
  end

  defp digest(secret, data) do
    <<mac :: [integer, size(160)]>> = :crypto.hmac(:sha, secret, data)
    Integer.to_char_list(mac, 16) |> IO.iodata_to_binary
  end

  @doc """
  Compares the two binaries completely, byte by byte,
  to avoid timing attacks.
  """
  def secure_compare(left, right) do
    if byte_size(left) == byte_size(right) do
      compare_each(left, right, true)
    else
      false
    end
  end

  defp compare_each(<<h, left :: binary>>, <<h, right :: binary>>, acc) do
    compare_each(left, right, acc)
  end

  defp compare_each(<<_, left :: binary>>, <<_, right :: binary>>, _acc) do
    compare_each(left, right, false)
  end

  defp compare_each(<<>>, <<>>, acc) do
    acc
  end
end

