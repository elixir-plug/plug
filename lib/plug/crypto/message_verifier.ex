defmodule Plug.Crypto.MessageVerifier do
  @moduledoc """
  `MessageVerifier` makes it easy to generate and verify messages
  which are signed to prevent tampering.

  For example, the cookie store uses this verifier to send data
  to the client. The data can be read by the client, but cannot be
  tampered with.
  """

  @delimiter "##"

  @doc """
  Decodes and verifies the encoded binary was not tampared with.
  """
  def verify(binary, secret) when is_binary(binary) and is_binary(secret) do
    case split(binary) do
      [content, digest] when content != "" and digest != "" ->
        if Plug.Crypto.secure_compare(digest(secret, content), digest) do
          decode(content)
        else
          :error
        end
      _ ->
        :error
    end
  end

  @doc """
  Signs a binary according to the given secret.
  """
  def sign(binary, secret) when is_binary(binary) and is_binary(secret) do
    encoded = Base.url_encode64(binary)
    encoded <> @delimiter <> digest(secret, encoded)
  end

  defp digest(secret, data) do
    :crypto.hmac(:sha, secret, data) |> Base.url_encode64
  end

  # TODO: Remove after backwards compatibility period
  defp split(binary) do
    case String.split(binary, @delimiter) do
      [_, _] = both -> both
      _ -> String.split(binary, "--")
    end
  end

  # TODO: Remove after backwards compatibility period
  defp decode(content) do
    case Base.url_decode64(content) do
      {:ok, binary} -> {:ok, binary}
      :error -> Base.decode64(content)
    end
  end
end
