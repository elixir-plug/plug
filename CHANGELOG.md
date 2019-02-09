# Changelog

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
