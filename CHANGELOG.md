## Changelog

## v0.9.0

* Enhancements
  * Add `Plug.Conn.full_path/1`
  * Add `Plug.CSRFProtection` that adds cross-forgery protection
  * Add `Plug.ErrorHandler` that allows an error page to be sent on crashes (instead of a blank one)
  * Support host option in `Plug.Router`

* Backwards incompatible changes
  * Add `Plug.Router.Utils.build_match/1` was renamed to `build_path_match/1`

## v0.8.4

* Bug fixes
  * Clean up `{:plug_conn, :sent}` messages from listener inbox and ensure connection works accross processes

* Deprecations
  * Deprecate `recycle/2` in favor of `recycle_cookies` in Plug.Test

## v0.8.3

* Enhancements
  * Use PKCS7 padding in MessageEncryptor (the same as OpenSSL)
  * Add support for custom serializers in cookie session store
  * Allow customization of key generation in cookie session store
  * Automatically import `Plug.Conn` in Plug builder
  * Render errors from Plug when using Ranch/Cowboy nicely
  * Provide `Plug.Crypto.secure_compare/2` for comparing binaries
  * Add `Plug.Debugger` for helpful pages whenever there is a failure during a request

* Deprecations
  * Deprecate `:accept` in favor of `:pass` in Plug.Parsers

## v0.8.2

* Enhancements
  * Add `Plug.Conn.Utils.media_type/1` to provide media type parsing with wildcard support
  * Do not print adapter data by default when inspecting the connection
  * Allow plug_status to simplify the definition of plug aware exceptions
  * Allow cache headers in `Plug.Static` to be turned off

* Bug fix
  * Support dots on header parameter parsing

## v0.8.1

* Enhancements
  * Add a `Plug.Parsers.JSON` that expects a JSON decoder as argument

* Bug fix
  * Properly populate `params` field for test connections
  * Fix `Plug.Logger` not reporting the proper path

## v0.8.0

* Enhancements
  * Add `fetch_session/2`, `fetch_params/2` and `fetch_cookies/2` so they can be pluggable
  * Raise an error message on invalid router indentifiers
  * Add `put_status/2` and support atom status codes
  * Add `secret_key_base` field to the connection

* Backwards incompatible changes
  * Add `encryption_salt` and `signing_salt` to the CookieStore and derive actual keys from `secret_key_base`

## v0.7.0

* Enhancements
  * Support Elixir 1.0.0-rc1
  * Support haltable pipelines with `Plug.Conn.halt/2`
  * Ensure both Plug.Builder and Plug.Router's `call/2` are overridable

* Bug fix
  * Properly report times in Logger

* Backwards incompatible changes
  * Remove support for Plug wrappers

## v0.6.0

* Enhancements
  * Add `Plug.Logger`
  * Add `conn.peer` and `conn.remote_ip`
  * Add `Plug.Conn.sendfile/5`
  * Allow `call/2` from `Plug.Builder` to be overridable

## v0.5.3

* Enhancements
  * Update to Cowboy v1.0.0
  * Update mime types list
  * Update to Elixir v0.15.0

## v0.5.2

* Enhancements
  * Update to Elixir v0.14.3
  * Cowboy adapter now returns `{:error,:eaddrinuse}` when port is already in use
  * Add `Plug.Test.recycle/2` that copies relevant data in between connections for future requests

## v0.5.1

* Enhancements
  * Add ability to configure when `Plug.Parsers` raises `UnsupportedMediaTypeError`
  * Add `Plug.Conn.Query.encode/1`
  * Add `CookieStore` for session

* Bug fixes
  * Ensure plug parses content-type with CRLF as LWS

## v0.5.0

* Enhancements
  * Update to Elixir v0.14.0
  * Update Cowboy adapter to v0.10.0
  * Add `Plug.Conn.read_body/2`

* Backwards incompatible changes
  * `Plug.Parsers` now expect `:length` instead of `:limit` and also accept `:read_length` and `:read_timeout`

## v0.4.4

* Enhancements
  * Update to Elixir v0.13.3

## v0.4.3

* Enhancements
  * Update to Elixir v0.13.2

## v0.4.2

* Enhancements
  * Update to Elixir v0.13.1

## v0.4.1

* Enhancements
  * Remove `:mime` dependency in favor of `Plug.MIME`
  * Improve errors when Cowboy is not available
  * First hex package release

## v0.4.0

* Enhancements
  * Support `before_send/1` callbacks
  * Add `Plug.Static`
  * Allow iodata as the body
  * Do not allow response headers to be set if the response was already sent
  * Add `Plug.Conn.private` to be used as storage by libraries/frameworks
  * Add `get_req_header` and `get_resp_header` for fetching request and response headers

* Backwards incompatible changes
  * `Plug.Connection` was removed in favor of `Plug.Conn`
  * `Plug.Conn` is now a struct
  * assigns, cookies, params and sessions have been converted to maps

## v0.3.0

* Definition of the Plug specification
