defmodule Plug.Crypto.MessageVerifier do
  @moduledoc """
  `MessageVerifier` makes it easy to generate and verify messages
  which are signed to prevent tampering.

  For example, the cookie store uses this verifier to send data
  to the client. The data can be read by the client, but cannot be
  tampered with.
  """

  @doc """
  Signs a message according to the given secret.
  """
  def sign(message, secret, digest_type \\ :sha256)
      when is_binary(message) and is_binary(secret) and digest_type in [:sha256, :sha384, :sha512] do
    hmac_sha2_sign(message, secret, digest_type)
  end

  @doc """
  Decodes and verifies the encoded binary was not tampered with.
  """
  def verify(signed, secret) when is_binary(signed) and is_binary(secret) do
    hmac_sha2_verify(signed, secret)
  end

  ## Signature Algorithms

  defp hmac_sha2_to_protected(:sha256), do: "HS256"
  defp hmac_sha2_to_protected(:sha384), do: "HS384"
  defp hmac_sha2_to_protected(:sha512), do: "HS512"

  defp hmac_sha2_to_digest_type("HS256"), do: :sha256
  defp hmac_sha2_to_digest_type("HS384"), do: :sha384
  defp hmac_sha2_to_digest_type("HS512"), do: :sha512

  defp hmac_sha2_sign(payload, key, digest_type) do
    protected = hmac_sha2_to_protected(digest_type)
    plain_text = signing_input(protected, payload)
    signature = :crypto.hmac(digest_type, key, plain_text)
    encode_token(plain_text, signature)
  end

  defp hmac_sha2_verify(signed, key) when is_binary(signed) and is_binary(key) do
    case decode_token(signed) do
      {protected, payload, plain_text, signature} when protected in ["HS256", "HS384", "HS512"] ->
        digest_type = hmac_sha2_to_digest_type(protected)
        challenge = :crypto.hmac(digest_type, key, plain_text)

        if Plug.Crypto.secure_compare(challenge, signature) do
          {:ok, payload}
        else
          :error
        end

      _ ->
        :error
    end
  end

  ## Helpers

  defp encode_token(plain_text, signature)
       when is_binary(plain_text) and is_binary(signature) do
    plain_text <> "." <> Base.url_encode64(signature, padding: false)
  end

  defp decode_token(token) do
    with [protected, payload, signature] <- String.split(token, ".", parts: 3),
         plain_text = protected <> "." <> payload,
         {:ok, protected} <- Base.url_decode64(protected, padding: false),
         {:ok, payload} <- Base.url_decode64(payload, padding: false),
         {:ok, signature} <- Base.url_decode64(signature, padding: false) do
      {protected, payload, plain_text, signature}
    else
      _ -> :error
    end
  end

  defp signing_input(protected, payload) when is_binary(protected) and is_binary(payload) do
    protected
    |> Base.url_encode64(padding: false)
    |> Kernel.<>(".")
    |> Kernel.<>(Base.url_encode64(payload, padding: false))
  end
end
