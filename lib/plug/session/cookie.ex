defmodule Plug.Session.COOKIE do
  @moduledoc """
  Stores the session in a cookie.

  Implements a cookie store. This cookie store is based on
  `Plug.MessageVerifier` which signs each cookie to ensure
  they won't be tampered with.

  Notice the cookie contents are still visible and therefore
  private data should never be put into such store.

  ## Options

  * `:secret` - secret token used to sign the cookie;

  ## Examples

      # Use the session plug with the table name
      plug Plug.Session, store: :cookie, key: "_my_app_session", secret: "a4f8d34f9"
  """

  @behaviour Plug.Session.Store

  alias Plug.MessageVerifier

  def init(opts) do
    secret = opts[:secret]

    cond do
      nil?(secret) ->
        raise ArgumentError, "cookie store expects a secret as option"
      byte_size(secret) < 64 ->
        raise ArgumentError, "cookie store secret must be at least 64 bytes"
      true ->
        opts
    end
  end

  def get(cookie, opts) do
    case MessageVerifier.verify opts[:secret], cookie do
      {:ok, value} -> {nil, value}
      :error       -> {nil, %{}}
    end
  end

  def put(_sid, term, opts) do
    MessageVerifier.generate opts[:secret], term
  end

  def delete(_sid, _opts) do
    :ok
  end
end
