# Changelog

## v1.10.4 (2020-08-07)

### Bug fixes

  * [Plug.Conn] Automatically set secure when deleting cookies to fix compatibility with SameSite

## v1.10.3 (2020-06-10)

### Enhancements

  * [Plug.SSL] Allow host exclusion to be checked dynamically

### Bug fixes

  * [Plug.Router] Fix router telemetry event to follow Telemetry specification. This corrects the telemetry event added on v1.10.1.

## v1.10.2 (2020-06-06)

### Bug fixes

  * [Plug] Make `:telemetry` a required dependency
  * [Plug.Test] Populate `:query_string` when params are passed in

### Enhancements

  * [Plug] Add `Plug.run/3` for running multiple Plugs at runtime
  * [Plug] Add `Plug.forward/4` for forwarding between Plugs

## v1.10.1 (2020-05-15)

### Enhancements

  * [Plug.Conn] Add option to disable uft-8 validation on query strings
  * [Plug.Conn] Support `:same_site` option when writing cookies
  * [Plug.Router] Add router dispatch telemetry events
  * [Plug.SSL] Support `:x_forwarded_host` and `:x_forwarded_port` on `:rewrite_on`

### Bug fixes

  * [Plug.Test] Ensure parameters are converted to string keys

## v1.10.0 (2020-03-24)

### Enhancements

  * [Plug.BasicAuth] Add `Plug.BasicAuth`
  * [Plug.Conn] Add built-in support for signed and encrypted cookies
  * [Plug.Exception] Allow to use atoms as statuses in the `plug_status` field for exceptions

### Bug fixes

  * [Plug.Router] Handle malformed URI as bad requests

## v1.9.0 (2020-02-07)

### Bug fixes

  * [Plug.Conn.Cookies] Make `decode` split on `;` only, remove `$`-prefix condition
  * [Plug.CSRFProtection] Generate url safe CSRF masks
  * [Plug.Parsers] Treat invalid content-types as parsing errors unless `:pass` is given
  * [Plug.Parsers] Ensure parameters are merged when falling back to `:pass` clause
  * [Plug.Parsers] Use HTTP status code 414 when query string is too long
  * [Plug.SSL] Rewrite port when rewriting a request coming to a standard port

### Enhancements

  * [Plug] Make Plug fully compatible with new Elixir child specs
  * [Plug.Exception] Add actions to exceptions that implement `Plug.Exception` and render actions in `Plug.Debugger` error page
  * [Plug.Parsers] Add option to skip utf8 validation
  * [Plug.Parsers] Make multipart support MFA for `:length` limit
  * [Plug.Static] Accept MFA for `:header` option
  
### Notes
  * When implementing the `Plug.Exception` protocol, if the new `actions` function is not implemented, a warning will printed during compilation.

## v1.8.3 (2019-07-28)

### Bug fixes

  * [Plug.Builder] Ensure init_mode option is respected within the Plug.Builder DSL itself
  * [Plug.Session] Fix dropping session with custom max_age

## v1.8.2 (2019-06-01)

### Enhancements

  * [Plug.CSRFProtection] Increase entropy and ensure forwards compatibility with future URL-safe CSRF tokens

## v1.8.1 (2019-06-01)

### Enhancements

  * [Plug.CSRFProtection] Allow state to be dumped from the session and provide an API to validate both state and tokens
  * [Plug.Session.Store] Add `get/1` to retrieve the store from a module/atom
  * [Plug.Static] Support Nginx range requests
  * [Plug.Telemetry] Allow extra options in `Plug.Telemetry` metadata

## v1.8.0 (2019-03-31)

### Enhancements

  * [Plug.Conn] Add `get_session/1` for retrieving the whole session
  * [Plug.CSRFProtection] Add `Plug.CSRFPRotection.load_state/2` and `Plug.CSRFPRotection.dump_state/0` to allow tokens to be generated in other processes
  * [Plug.Parsers] Allow unnamed parts in multipart parser via `:include_unnamed_parts_at`
  * [Plug.Router] Wrap router dispatch in a connection checkpoint to avoid losing information attached to the connection in error cases
  * [Plug.Telemetry] Add `Plug.Telemetry` to facilitate with telemetry integration

### Bug fixes

  * [Plug.Conn.Status] Use IANA registered status code for HTTP 425
  * [Plug.RequestID] Reduce RequestID size by relying on base64 encoding
  * [Plug.Static] Ensure etags are quoted correctly
  * [Plug.Static] Ensure vary header is set in 304 response
  * [Plug.Static] Omit content-encoding header in 304 responses

## v1.7.2 (2019-02-09)

  * [Plug.Parser.MULTIPART] Support UTF-8 filename encoding in multipart parser
  * [Plug.Router] Add `builder_opts` support to `:dispatch` plug
  * [Plug.SSL] Do not disable client renegotiation
  * [Plug.Upload] Raise when we can't write to disk during upload

## v1.7.1 (2018-10-24)

  * [Plug.Adapters.Cowboy] Less verbose output when plug_cowboy is missing
  * [Plug.Adapters.Cowboy2] Less verbose output when plug_cowboy is missing

## v1.7.0 (2018-10-20)

### Enhancements

  * [Plug] Require Elixir v1.4+
  * [Plug.Session] Support MFAs for cookie session secrets
  * [Plug.Test] Add `put_peer_data`
  * [Plug.Adapters.Cowboy] Extract into [plug_cowboy][plug_cowboy]
  * [Plug.Adapters.Cowboy2] Extract into [plug_cowboy][plug_cowboy]

### Bug fixes

  * [Plug.SSL] Don't redirect excluded hosts on Plug.SSL

### Breaking Changes

  * [Plug] Applications may need to add `:plug_cowboy` to your deps to use this version

## v1.6

See [CHANGELOG in the v1.6 branch](https://github.com/elixir-plug/plug/blob/v1.6/CHANGELOG.md).

  [plug_cowboy]: https://github.com/elixir-plug/plug_cowboy
