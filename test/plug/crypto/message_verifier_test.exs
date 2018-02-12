defmodule Plug.Crypto.MessageVerifierTest do
  use ExUnit.Case, async: true

  alias Plug.Crypto.MessageVerifier, as: MV

  test "generates a signed message" do
    [protected, payload, signature] = String.split(MV.sign("hello world", "secret"), ".")
    assert Base.url_decode64(protected, padding: false) == {:ok, "HS256"}
    assert Base.url_decode64(payload, padding: false) == {:ok, "hello world"}
    assert byte_size(signature) == 43

    [protected, payload, signature] = String.split(MV.sign("hello world", "secret", :sha384), ".")
    assert Base.url_decode64(protected, padding: false) == {:ok, "HS384"}
    assert Base.url_decode64(payload, padding: false) == {:ok, "hello world"}
    assert byte_size(signature) == 64

    [protected, payload, signature] = String.split(MV.sign("hello world", "secret", :sha512), ".")
    assert Base.url_decode64(protected, padding: false) == {:ok, "HS512"}
    assert Base.url_decode64(payload, padding: false) == {:ok, "hello world"}
    assert byte_size(signature) == 86
  end

  test "verifies a signed message" do
    [protected, payload, signature] = String.split(MV.sign("hello world", "secret"), ".")

    assert MV.verify(protected <> "." <> payload <> "." <> signature, "secret") ==
             {:ok, "hello world"}

    [protected, payload, signature] = String.split(MV.sign("hello world", "secret", :sha384), ".")

    assert MV.verify(protected <> "." <> payload <> "." <> signature, "secret") ==
             {:ok, "hello world"}

    [protected, payload, signature] = String.split(MV.sign("hello world", "secret", :sha512), ".")

    assert MV.verify(protected <> "." <> payload <> "." <> signature, "secret") ==
             {:ok, "hello world"}
  end

  test "does not verify a signed message if secret changed" do
    signed = MV.sign("hello world", "secret")
    assert MV.verify(signed, "secreto") == :error

    signed = MV.sign("hello world", "secret", :sha384)
    assert MV.verify(signed, "secreto") == :error

    signed = MV.sign("hello world", "secret", :sha512)
    assert MV.verify(signed, "secreto") == :error
  end

  test "does not verify a tampered message" do
    # Tampered payload
    payload = Base.url_encode64("another world", padding: false)
    [protected, _payload, signature] = String.split(MV.sign("hello world", "secret"), ".")
    assert MV.verify(protected <> "." <> payload <> "." <> signature, "secret") == :error

    [protected, _payload, signature] =
      String.split(MV.sign("hello world", "secret", :sha384), ".")

    assert MV.verify(protected <> "." <> payload <> "." <> signature, "secret") == :error

    [protected, _payload, signature] =
      String.split(MV.sign("hello world", "secret", :sha512), ".")

    assert MV.verify(protected <> "." <> payload <> "." <> signature, "secret") == :error

    # Tampered protected
    [_protected, payload, signature] = String.split(MV.sign("hello world", "secret"), ".")
    protected = Base.url_encode64("HS384", padding: false)
    assert MV.verify(protected <> "." <> payload <> "." <> signature, "secret") == :error

    [_protected, payload, signature] =
      String.split(MV.sign("hello world", "secret", :sha384), ".")

    protected = Base.url_encode64("HS512", padding: false)
    assert MV.verify(protected <> "." <> payload <> "." <> signature, "secret") == :error

    [_protected, payload, signature] =
      String.split(MV.sign("hello world", "secret", :sha512), ".")

    protected = Base.url_encode64("HS256", padding: false)
    assert MV.verify(protected <> "." <> payload <> "." <> signature, "secret") == :error
  end
end
