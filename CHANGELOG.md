## Changelog

## v1.6.2 (2018-08-04)

  * Add `Plug.Test.put_peer_data/2`
  * Support MFAs for cookie session secrets
  * Allow `builder_opts()` to be passed to inner plugs in `Plug.Builder`

## v1.6.1 (2018-07-05)

* Enhancements
  * Raise on unknown `Plug.SSL` cipher_suites
  * Document Cowboy 2 usage with unix sockets
  * Add `Plug.Debugger` banner for custom page details
  * Do not crash error reporter for Cowboy 2 on undefined port

## v1.6.0 (2018-06-16)

* Enhancements
  * Add `Plug.Conn.inform/3` and `Plug.Conn.inform!/3` to support HTTP/2 informational responses
  * Add `Plug.Conn.get_peer_data/1` to read client information such as address, port and ssl cert
  * Add `Plug.Conn.get_http_protocol/1`
  * Add `Plug.SSL.configure/1` to hold common SSL configuration and enable `reuse_sessions` and `secure_renegotiate` by default in adapters
  * Add the `cipher_suite` option to provide secure defaults for a `:strong` or a `:compatible` TLS configuration.
  * `Plug.SSL` skips HSTS by default on localhost. The list of hosts to exclude is configurable

## v1.5.1 (2018-05-17)

* Enhancements
  * Implement missing access behaviour for `Plug.Conn.Unfetched` to provide better error messages
  * Add function plug forwarding to `Plug.Router`
  * Support custom body readers in `Plug.Parsers`
  * Introduce `merge_assigns/2` and `merge_private/2`
  * Add `Plug.Conn.WrapperError.reraise/1` and `Plug.Conn.WrapperError.reraise/4` to deal with upcoming changes in Elixir v1.7

* Bug fixes
  * Properly convert all list headers to map when using Cowboy 2
  * Do not require certfile/keyfile with ssl if sni options are present

## v1.5.0 (2018-03-09)

* Enhancements
  * Add `init_mode` to `Plug.Builder` for runtime initialization
  * Allow passing MFA tuple to JSON decoder
  * Allow `:log_error_on_incomplete_requests` to be disabled for Cowboy adapters
  * Support Cowboy 2.2 with HTTP/2 support
  * Optimize `Plug.RequestID` on machines with multiple cores
  * Add `Plug.Conn.push/3` and `Plug.Conn.push!/3` to support HTTP/2 server push
  * Add `Plug.Conn.request_url/1`
  * Optimise `Plug.HTML.html_escape_to_iodata/1`
  * Add `Plug.Router.match_path/1`
  * Log on `Plug.SSL` redirects
  * Allow `Plug.CSRFProtection` tokens to be generated and matched with host specific information
  * Add `Plug.Conn.prepend_resp_headers/3`
  * Add `Plug.Status.reason_atom/1`

* Bug fixes
  * Ensure CSRF token is not deleted if plug is called twice
  * Do not fail on empty multipart body without boundary
  * Do not decode empty query string pairs
  * Consider both the connection protocol and `x-forwarded-proto` when redirecting on `Plug.SSL`

* Deprecations
  * Deprecate Plug.Conn's Collectable protocol implementation

## v1.4

See [CHANGELOG in the v1.4 branch](https://github.com/elixir-plug/plug/blob/v1.4/CHANGELOG.md).
