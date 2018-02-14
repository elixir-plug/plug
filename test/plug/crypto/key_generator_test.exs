defmodule Plug.Crypto.KeyGeneratorTest do
  use ExUnit.Case, async: true

  import Plug.Crypto.KeyGenerator
  use Bitwise

  @max_length bsl(1, 32) - 1

  test "returns an error for length exceeds max_length" do
    assert_raise ArgumentError, ~r/length must be less than or equal/, fn ->
      generate("secret", "salt", length: @max_length + 1)
    end
  end

  test "it works" do
    key = generate("password", "salt", iterations: 1, length: 20, digest: :sha)
    assert byte_size(key) == 20
    assert to_hex(key) == "0c60c80f961f0e71f3a9b524af6012062fe037a6"

    key = generate("password", "salt", iterations: 2, length: 20, digest: :sha)
    assert byte_size(key) == 20
    assert to_hex(key) == "ea6c014dc72d6f8ccd1ed92ace1d41f0d8de8957"

    key = generate("password", "salt", iterations: 4096, length: 20, digest: :sha)
    assert byte_size(key) == 20
    assert to_hex(key) == "4b007901b765489abead49d926f721d065a429c1"

    key =
      generate(
        "passwordPASSWORDpassword",
        "saltSALTsaltSALTsaltSALTsaltSALTsalt",
        iterations: 4096,
        length: 25,
        digest: :sha
      )

    assert byte_size(key) == 25
    assert to_hex(key) == "3d2eec4fe41c849b80c8d83662c0e44a8b291a964cf2f07038"

    key = generate("pass\0word", "sa\0lt", iterations: 4096, length: 16, digest: :sha)
    assert byte_size(key) == 16
    assert to_hex(key) == "56fa6aa75548099dcc37d7f03425e0c3"

    key = generate("password", "salt", digest: :sha)
    assert byte_size(key) == 32
    assert to_hex(key) == "6e88be8bad7eae9d9e10aa061224034fed48d03fcbad968b56006784539d5214"

    key = generate("password", "salt")
    assert byte_size(key) == 32
    assert to_hex(key) == "632c2812e46d4604102ba7618e9d6d7d2f8128f6266b4a03264d2a0460b7dcb3"

    key = generate("password", "salt", iterations: 1000, length: 64, digest: :sha)
    assert byte_size(key) == 64

    assert to_hex(key) ==
             "6e88be8bad7eae9d9e10aa061224034fed48d03fcbad968b56006784539d5214ce970d912ec2049b04231d47c2eb88506945b26b2325e6adfeeba08895ff9587"
  end

  def to_hex(value), do: Base.encode16(value, case: :lower)
end
