defmodule Plug.Crypto.MessageEncryptor do
  @moduledoc ~S"""
  `MessageEncryptor` is a simple way to encrypt values which get stored
  somewhere you don't trust.

  The encrypted key, initialization vector, cipher text, and cipher tag
  are base64url encoded and returned to you.

  This can be used in situations similar to the `Plug.Crypto.MessageVerifier`,
  but where you don't want users to be able to determine the value of the payload.

  ## Example

      secret_key_base = "072d1e0157c008193fe48a670cce031faa4e..."
      encrypted_cookie_salt = "encrypted cookie"
      encrypted_signed_cookie_salt = "signed encrypted cookie"

      secret = KeyGenerator.generate(secret_key_base, encrypted_cookie_salt)
      sign_secret = KeyGenerator.generate(secret_key_base, encrypted_signed_cookie_salt)

      data = "José"
      encrypted = MessageEncryptor.encrypt(data, secret, sign_secret)
      decrypted = MessageEncryptor.decrypt(encrypted, secret, sign_secret)
      decrypted # => {:ok, "José"}

  """

  @doc """
  Encrypts a message using authenticated encryption.
  """
  def encrypt(message, secret, sign_secret)
      when is_binary(message) and is_binary(secret) and is_binary(sign_secret) do
    aes128_gcm_encrypt(message, secret, sign_secret)
  rescue
    e -> reraise e, Plug.Crypto.prune_args_from_stacktrace(System.stacktrace())
  end

  @doc """
  Decrypts a message using authenticated encryption.
  """
  def decrypt(encrypted, secret, sign_secret)
      when is_binary(encrypted) and is_binary(secret) and is_binary(sign_secret) do
    aes128_gcm_decrypt(encrypted, secret, sign_secret)
  rescue
    e -> reraise e, Plug.Crypto.prune_args_from_stacktrace(System.stacktrace())
  end

  # Encrypts and authenticates a message using AES128-GCM mode.
  #
  # A random 128-bit content encryption key (CEK) is generated for
  # every message which is then encrypted with `aes_gcm_key_wrap/3`.
  defp aes128_gcm_encrypt(plain_text, secret, sign_secret) when bit_size(secret) > 256 do
    aes128_gcm_encrypt(plain_text, binary_part(secret, 0, 32), sign_secret)
  end

  defp aes128_gcm_encrypt(plain_text, secret, sign_secret)
       when is_binary(plain_text) and bit_size(secret) in [128, 192, 256] and
              is_binary(sign_secret) do
    key = :crypto.strong_rand_bytes(16)
    iv = :crypto.strong_rand_bytes(12)
    aad = "A128GCM"
    {cipher_text, cipher_tag} = block_encrypt(:aes_gcm, key, iv, {aad, plain_text})
    encrypted_key = aes_gcm_key_wrap(key, secret, sign_secret)
    encode_token(aad, encrypted_key, iv, cipher_text, cipher_tag)
  end

  # Verifies and decrypts a message using AES128-GCM mode.
  #
  # Decryption will never be performed prior to verification.
  #
  # The encrypted content encryption key (CEK) is decrypted
  # with `aes_gcm_key_unwrap/3`.
  defp aes128_gcm_decrypt(cipher_text, secret, sign_secret) when bit_size(secret) > 256 do
    aes128_gcm_decrypt(cipher_text, binary_part(secret, 0, 32), sign_secret)
  end

  defp aes128_gcm_decrypt(cipher_text, secret, sign_secret)
       when is_binary(cipher_text) and bit_size(secret) in [128, 192, 256] and
              is_binary(sign_secret) do
    case decode_token(cipher_text) do
      {aad = "A128GCM", encrypted_key, iv, cipher_text, cipher_tag}
      when bit_size(iv) === 96 and bit_size(cipher_tag) === 128 ->
        encrypted_key
        |> aes_gcm_key_unwrap(secret, sign_secret)
        |> case do
          {:ok, key} ->
            block_decrypt(:aes_gcm, key, iv, {aad, cipher_text, cipher_tag})

          _ ->
            :error
        end
        |> case do
          plain_text when is_binary(plain_text) ->
            {:ok, plain_text}

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp block_encrypt(algo, key, iv, payload) do
    :crypto.block_encrypt(algo, key, iv, payload)
  catch
    :error, :notsup -> raise_notsup(algo)
  end

  defp block_decrypt(algo, key, iv, payload) do
    :crypto.block_decrypt(algo, key, iv, payload)
  catch
    :error, :notsup -> raise_notsup(algo)
  end

  defp raise_notsup(algo) do
    raise "the algorithm #{inspect(algo)} is not supported by your Erlang/OTP installation. " <>
            "Please make sure it was compiled with the correct OpenSSL/BoringSSL bindings"
  end

  # Wraps a decrypted content encryption key (CEK) with secret and
  # sign_secret using AES GCM mode.
  #
  # See: https://tools.ietf.org/html/rfc7518#section-4.7
  defp aes_gcm_key_wrap(cek, secret, sign_secret) when bit_size(secret) > 256 do
    aes_gcm_key_wrap(cek, binary_part(secret, 0, 32), sign_secret)
  end

  defp aes_gcm_key_wrap(cek, secret, sign_secret)
       when bit_size(cek) in [128, 192, 256] and bit_size(secret) in [128, 192, 256] and
              is_binary(sign_secret) do
    iv = :crypto.strong_rand_bytes(12)
    {cipher_text, cipher_tag} = block_encrypt(:aes_gcm, secret, iv, {sign_secret, cek})
    cipher_text <> cipher_tag <> iv
  end

  # Unwraps an encrypted content encryption key (CEK) with secret and
  # sign_secret using AES GCM mode.
  #
  # See: https://tools.ietf.org/html/rfc7518#section-4.7
  defp aes_gcm_key_unwrap(wrapped_cek, secret, sign_secret) when bit_size(secret) > 256 do
    aes_gcm_key_unwrap(wrapped_cek, binary_part(secret, 0, 32), sign_secret)
  end

  defp aes_gcm_key_unwrap(wrapped_cek, secret, sign_secret)
       when bit_size(secret) in [128, 192, 256] and is_binary(sign_secret) do
    wrapped_cek
    |> case do
      <<cipher_text::128-bitstring, cipher_tag::128-bitstring, iv::96-bitstring>> ->
        block_decrypt(:aes_gcm, secret, iv, {sign_secret, cipher_text, cipher_tag})

      <<cipher_text::192-bitstring, cipher_tag::128-bitstring, iv::96-bitstring>> ->
        block_decrypt(:aes_gcm, secret, iv, {sign_secret, cipher_text, cipher_tag})

      <<cipher_text::256-bitstring, cipher_tag::128-bitstring, iv::96-bitstring>> ->
        block_decrypt(:aes_gcm, secret, iv, {sign_secret, cipher_text, cipher_tag})

      _ ->
        :error
    end
    |> case do
      cek when bit_size(cek) in [128, 192, 256] ->
        {:ok, cek}

      _ ->
        :error
    end
  end

  defp encode_token(protected, encrypted_key, iv, cipher_text, cipher_tag) do
    Base.url_encode64(protected, padding: false)
    |> Kernel.<>(".")
    |> Kernel.<>(Base.url_encode64(encrypted_key, padding: false))
    |> Kernel.<>(".")
    |> Kernel.<>(Base.url_encode64(iv, padding: false))
    |> Kernel.<>(".")
    |> Kernel.<>(Base.url_encode64(cipher_text, padding: false))
    |> Kernel.<>(".")
    |> Kernel.<>(Base.url_encode64(cipher_tag, padding: false))
  end

  defp decode_token(token) do
    with [protected, encrypted_key, iv, cipher_text, cipher_tag] <-
           String.split(token, ".", parts: 5),
         {:ok, protected} <- Base.url_decode64(protected, padding: false),
         {:ok, encrypted_key} <- Base.url_decode64(encrypted_key, padding: false),
         {:ok, iv} <- Base.url_decode64(iv, padding: false),
         {:ok, cipher_text} <- Base.url_decode64(cipher_text, padding: false),
         {:ok, cipher_tag} <- Base.url_decode64(cipher_tag, padding: false) do
      {protected, encrypted_key, iv, cipher_text, cipher_tag}
    else
      _ -> :error
    end
  end
end
