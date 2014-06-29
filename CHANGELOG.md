# v0.5.1

* Enhancements
  * Add ability to configure when `Plug.Parsers` raises `UnsupportedMediaTypeError`
  * Add `Plug.Conn.Query.encode/1`
  * Add `CookieStore` for session

* Bug fixes
  * Ensure plug parses content-type with CRLF as LWS

# v0.5.0

* Enhancements
  * Update to Elixir v0.14.0
  * Update Cowboy adapter to v0.10.0
  * Add `Plug.Conn.read_body/2`

* Backwards incompatible changes
  * `Plug.Parsers` now expect `:length` instead of `:limit` and also accept `:read_length` and `:read_timeout`

# v0.4.4

* Enhancements
  * Update to Elixir v0.13.3

# v0.4.3

* Enhancements
  * Update to Elixir v0.13.2

# v0.4.2

* Enhancements
  * Update to Elixir v0.13.1

# v0.4.1

* Enhancements
  * Remove `:mime` dependency in favor of `Plug.MIME`
  * Improve errors when Cowboy is not available
  * First hex package release

# v0.4.0

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

# v0.3.0

* Definition of the Plug specification
