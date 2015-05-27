defmodule Plug.Conn.Status do
  @moduledoc """
  Conveniences for working with status codes.
  """

  statuses = [
    continue: 100,
    switching_protocols: 101,
    processing: 102,
    ok: 200,
    created: 201,
    accepted: 202,
    non_authoritative_information: 203,
    no_content: 204,
    reset_content: 205,
    partial_content: 206,
    multi_status: 207,
    already_reported: 208,
    instance_manipulation_used: 226,
    multiple_choices: 300,
    moved_permanently: 301,
    found: 302,
    see_other: 303,
    not_modified: 304,
    use_proxy: 305,
    reserved: 306,
    temporary_redirect: 307,
    permanent_redirect: 308,
    bad_request: 400,
    unauthorized: 401,
    payment_required: 402,
    forbidden: 403,
    not_found: 404,
    method_not_allowed: 405,
    not_acceptable: 406,
    proxy_authentication_required: 407,
    request_timeout: 408,
    conflict: 409,
    gone: 410,
    length_required: 411,
    precondition_failed: 412,
    request_entity_too_large: 413,
    request_uri_too_long: 414,
    unsupported_media_type: 415,
    requested_range_not_satisfiable: 416,
    expectation_failed: 417,
    im_a_teapot: 418,
    misdirected_request: 421,
    unprocessable_entity: 422,
    locked: 423,
    failed_dependency: 424,
    upgrade_required: 426,
    precondition_required: 428,
    too_many_requests: 429,
    request_header_fields_too_large: 431,
    internal_server_error: 500,
    not_implemented: 501,
    bad_gateway: 502,
    service_unavailable: 503,
    gateway_timeout: 504,
    http_version_not_supported: 505,
    variant_also_negotiates: 506,
    insufficient_storage: 507,
    loop_detected: 508,
    not_extended: 510,
    network_authentication_required: 511
  ]

  doc = Enum.map(statuses, fn {atom, code} ->
    "  * `#{inspect atom}` - #{code}\n"
  end)

  @doc """
  Returns the status code given an integer or a known atom.

  ## Known status codes

  The following status codes can be given as atoms with their
  respective value shown next:

  #{doc}
  """
  @spec code(integer | atom) :: integer
  def code(integer_or_atom)

  def code(integer) when integer in 100..999 do
    integer
  end

  for {atom, code} <- statuses do
    def code(unquote(atom)), do: unquote(code)
  end
end
