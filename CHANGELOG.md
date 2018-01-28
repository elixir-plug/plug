## Changelog

## v1.5.0-rc.0

* Enhancements
  * Allow `:log_error_on_incomplete_requests` to be disabled for Cowboy adapters
  * Support Cowboy 2.1 with HTTP/2 support
  * Optimize Plug.RequestID on machines with multiple cores
  * Add `Plug.Conn.push/3` and `Plug.Conn.push!/3` to support HTTP/2 server push
  * Add `Plug.Conn.request_url/1`
  * Optimise `Plug.HTML.html_escape_to_iodata/1`
  * Add `Plug.Router.match_path/1`

* Bug fixes
  * Ensure CSRF token is not deleted if plug is called twice
  * Do not fail on empty multipart body without boundary
  * Do not decode empty query string pairs

## v1.4

See [CHANGELOG in the v1.4 branch](https://github.com/elixir-plug/plug/blob/v1.4/CHANGELOG.md).
