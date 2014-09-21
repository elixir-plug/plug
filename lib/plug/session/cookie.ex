defmodule Plug.Session.COOKIE do
  @moduledoc """
  Stores the session in a cookie.

  Implements a cookie store. This cookie store is based on
  `Plug.MessageVerifier` which signs each cookie to ensure
  they won't be tampered with.

  Notice the cookie contents are still visible and therefore
  private data should never be put into such store.

  ## Options

  * `:encrypt` - specify whether to encrypt cookies, default: true;
  * `:secret_key_base` - a base key used to generate psuedo-random keys for
                         encrypting/decrypting, signing/verifying cookies;
  * `:encryption_salt` - a salt used with `:secret_key_base` to generate a key
                         for encrypting/decrypting a cookie.
  * `:signing_salt` - a salt used with `:secret_key_base` to generate a key
                      for signing/verifying a cookie.

  ## Examples

      # Use the session plug with the table name
      plug Plug.Session, store: :cookie,
                         key: "_my_app_session",
                         secret_key_base: Application.get_env(:plug, :secret_key_base),
                         encryption_salt: Application.get_env(:plug, :encryption_salt),
                         signing_salt:    Application.get_env(:plug, :signing_salt)
  """

  @behaviour Plug.Session.Store

  alias Plug.Crypto.KeyGenerator
  alias Plug.Crypto.MessageVerifier
  alias Plug.Crypto.MessageEncryptor

  def init(opts) do
    %{secret_key_base: validate_secret_key_base(opts),
      encryption_key: generate_encryption_key(opts),
      signing_key: generate_signing_key(opts)}
  end

  def get(cookie, opts) do
    if key = opts.encryption_key do
      MessageEncryptor.verify_and_decrypt(cookie, key, opts.signing_key)
    else
      MessageVerifier.verify(cookie, opts.signing_key)
    end |> decode()
  end

  def put(_sid, term, opts) do
    binary = encode(term)
    if key = opts.encryption_key do
      MessageEncryptor.encrypt_and_sign(binary, key, opts.signing_key)
    else
      MessageVerifier.sign(binary, opts.signing_key)
    end
  end

  def delete(_sid, _opts) do
    :ok
  end

  defp encode(term), do:
    :erlang.term_to_binary(term)

  defp decode({:ok, binary}), do:
    {nil, :erlang.binary_to_term(binary)}
  defp decode(:error), do:
    {nil, %{}}

  defp validate_secret_key_base(opts) do
    cond do
      is_nil(opts[:secret_key_base]) ->
        raise ArgumentError, "cookie store expects a :secret_key_base option"
      byte_size(opts[:secret_key_base]) < 64 ->
        raise ArgumentError, "cookie store :secret_key_base must be at least 64 bytes"
      true ->
        opts
    end
  end

  defp generate_signing_key(opts) do
    case opts[:signing_salt] do
      nil ->
        raise ArgumentError, "cookie store expects a :signing_salt option"
      salt ->
        KeyGenerator.generate(opts[:secret_key_base], salt, cache: Plug.Keys)
    end
  end

  defp generate_encryption_key(opts) do
    if Keyword.get(opts, :encrypt, true) do
      case opts[:encryption_salt] do
        nil ->
          raise ArgumentError, "encrypted cookies expect an :encryption_salt option"
        salt ->
          KeyGenerator.generate(opts[:secret_key_base], salt, cache: Plug.Keys)
      end
    end
  end
end
