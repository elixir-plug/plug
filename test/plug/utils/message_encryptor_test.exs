defmodule Plug.Utils.MessageEncryptorTest do
  use ExUnit.Case, async: true

  alias Plug.Utils.KeyGenerator, as: KG
  alias Plug.Utils.MessageEncryptor, as: ME

  @secret_key_base "072d1e0157c008193fe48a670cce031faa4e6844b84326f6d31de759ad1820a928c9fc288c756d847b96c06afcdb8f04f80f38a84382028ebd6a783b59ab90b8"
  @encrypted_cookie_salt "encrypted cookie"
  @encrypted_signed_cookie_salt "signed encrypted cookie"

  setup do
    secret = KG.generate(@secret_key_base, @encrypted_cookie_salt)
    sign_secret = KG.generate(@secret_key_base, @encrypted_signed_cookie_salt)
    encryptor = ME.new(secret, sign_secret)
    {:ok, %{encryptor: encryptor}}
  end

  test "it encrypts/decrypts a message", %{encryptor: encryptor} do
    data = %{current_user: %{name: "José"}}
    encrypted = ME.encrypt_and_sign(encryptor, data)
    decrypted = ME.decrypt_and_verify(encryptor, encrypted)
    assert "José" == decrypted.current_user.name
  end
end
