defmodule Plug.Session do
  @moduledoc """
  A plug to handle session cookies and session stores.

  The session is accessed via functions on `Plug.Connection`.

  Cookies and session has to be fetched with `Plug.Connection.fetch_cookies/1`
  and `Plug.Connection.fetch_session/1` before the session can be accessed.

  ## Session stores

  See `Plug.Session.Store` for the specification session stores are required to
  implement.

  Plug ships with the following session stores:

  * `Plug.Session.ETSStore`

  ## Options

  * `:store` - session store module (required);
  * `:key` - session cookie key (required);
  * `:domain` - see `Plug.Connection.put_resp_cookies/4`;
  * `:max_age` - see `Plug.Connection.put_resp_cookies/4`;
  * `:path` - see `Plug.Connection.put_resp_cookies/4`;
  * `:secure` - see `Plug.Connection.put_resp_cookies/4`;

  Additional options can be given to the session store, see the store's
  documentation for the options it accepts.

  ## Examples

      plug Plug.Session, store: Plug.Session.ETSStore, key: "sid", secure: true, table: :session
  """

  alias Plug.Connection
  @behaviour Plug

  @cookie_opts [:domain, :max_age, :path, :secure]

  defrecordp :config, [:store, :store_config, :key, :cookie_opts]

  def init(opts) do
    store        = Keyword.fetch!(opts, :store)
    key          = Keyword.fetch!(opts, :key)
    cookie_opts  = Keyword.take(opts, @cookie_opts)
    store_opts   = Keyword.drop(opts, [:store, :key] ++ @cookie_opts)
    store_config = store.init(store_opts)

    config(store: store, store_config: store_config, key: key,
           cookie_opts: cookie_opts)
  end

  def call(conn, config) do
    Connection.assign_private(conn, :plug_session_fetch, fetch_session(config))
  end

  defp fetch_session(config) do
    config(store: store, store_config: store_config, key: key) = config

    fn conn ->
      if sid = conn.cookies[key] do
        session = store.get(sid, store_config)
      end

      conn
      |> Connection.assign_private(:plug_session, session || [])
      |> Connection.assign_private(:plug_session_info, nil)
      |> Connection.assign_private(:plug_session_fetch, &(&1))
      |> Connection.register_before_send(before_send(config))
    end
  end

  defp before_send(config) do
    config(store: store, store_config: store_config, key: key,
           cookie_opts: cookie_opts) = config

    fn conn ->
      sid = conn.cookies[key]

      case conn.private[:plug_session_info] do
        :write ->
          sid = store.put(sid, conn.private[:plug_session], store_config)
        :drop ->
          sid = nil
          store.destroy(sid, store_config)
        :renew ->
          store.destroy(sid, store_config)
          sid = store.put(nil, conn.private[:plug_session], store_config)
        nil ->
          :ok
      end

      if sid do
        conn = Connection.put_resp_cookie(conn, key, sid, cookie_opts)
      end

      conn
    end
  end
end
