defmodule Plug.Crypto.MessageEncryptorTest do
  use ExUnit.Case, async: true

  alias Plug.Crypto.MessageEncryptor, as: ME

  @right String.duplicate("abcdefgh", 4)
  @wrong String.duplicate("12345678", 4)

  test "it encrypts/decrypts a message" do
    data = <<0, "hełłoworld", 0>>
    encrypted = ME.encrypt_and_sign(<<0, "hełłoworld", 0>>, @right, @right)

    decrypted = ME.verify_and_decrypt(encrypted, @right, @wrong)
    assert decrypted == :error

    decrypted = ME.verify_and_decrypt(encrypted, @wrong, @right)
    assert decrypted == :error

    decrypted = ME.verify_and_decrypt(encrypted, @right, @right)
    assert decrypted == {:ok, data}
  end
end
