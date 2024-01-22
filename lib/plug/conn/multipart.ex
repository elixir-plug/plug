# Copyright (c) 2014-2015, Loïc Hoguin <essen@ninenines.eu>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

defmodule Plug.Conn.Multipart do
  # The multipart format is defined in RFC 2045.

  @doc """
  Parse the headers for the next multipart part.

  This function skips any preamble before the boundary.
  The preamble may be retrieved using parse_body/2.

  This function will accept input of any size, it is
  up to the caller to limit it if needed.
  """
  @spec parse_headers(binary(), binary()) :: :more | {:more, binary()} | {:ok, Plug.Conn.headers(), binary()} | {:done, binary()}

  def parse_headers(<<"--", stream::bits>>, boundary) do
    boundarySize = byte_size(boundary)
    case stream do
      # Last boundary. Return the epilogue.
      << _boundary::binary-size(boundarySize), "--", stream2::bits >> -> {:done, stream2}
      << _boundary::binary-size(boundarySize), stream2::bits >> ->
        # We have all the headers only if there is a \r\n\r\n
        # somewhere in the data after the boundary.
        if String.match?(stream2, ~r/\r\n\r\n/) do
          before_parse_headers(stream2)
        else
          :more
        end
      # If there isn't enough to represent Boundary \r\n\r\n
      # then we definitely don't have all the headers.
      _ when byte_size(stream) < byte_size(boundary) + 4 -> :more
      # Otherwise we have preamble data to skip.
      # We still got rid of the first two misleading bytes.
      _ -> skip_preamble(stream, boundary)
    end
  end
  def parse_headers(stream, boundary), do: skip_preamble(stream, boundary)

  @doc """
  Parse the body of the current multipart part.

  The body is everything until the next boundary.
  """
  @spec parse_body(binary(), binary()) :: {:ok, binary()} | {:ok, binary(), binary()} | :done | {:done, binary()} | {:done, binary(), binary()}
  def parse_body(stream, boundary) do
    boundarySize = byte_size(boundary)
    case stream do
      << "--", _boundary::binary-size(boundarySize), _::bits >> -> :done
      _ ->
        case :binary.match(stream, << "\r\n--", boundary::bits >>) do
          # No boundary, check for a possible partial at the end.
          # Return more or less of the body depending on the result.
          :nomatch ->
            streamSize = byte_size(stream)
            from = streamSize - boundarySize - 3
            matchOpts =
              if from < 0 do
                # Binary too small to contain boundary, check it fully.
                []
              else
                # Optimize, only check the end of the binary.
                [{:scope, {from, streamSize - from}}]
              end
            case :binary.match(stream, <<"\r">>, matchOpts) do
              :nomatch -> {:ok, stream}
              {pos, _} ->
                case stream do
                  << body::binary-size(pos) >> -> {:ok, body}
                  << body::binary-size(pos), rest::bits >> -> {:ok, body, rest}
                end
            end
          # Boundary found, this is the last chunk of the body.
          {pos, _} ->
            case stream do
              << body::binary-size(pos), "\r\n" >> -> {:done, body}
              << body::binary-size(pos), "\r\n", rest::bits >> -> {:done, body, rest}
              << body::binary-size(pos), rest::bits >> -> {:done, body, rest}
            end
        end
    end
  end

  # We need to find the boundary and a \r\n\r\n after that.
  # Since the boundary isn't at the start, it must be right
  # after a \r\n too.
  defp skip_preamble(stream, boundary) do
    case :binary.match(stream, <<"\r\n--", boundary::bits >>) do
      # No boundary, need more data.
      :nomatch ->
        # We can safely skip the size of the stream
        # minus the last 3 bytes which may be a partial boundary.
        skipSize = byte_size(stream) - 3
        if skipSize > 0 do
            << _::binary-size(skipSize), stream2::bits >> = stream
          {:more, stream2}
        else
          :more
        end
      {start, length} ->
        start2 = start + length
        << _::binary-size(start2), stream2::bits >> = stream
        case stream2 do
          # Last boundary. Return the epilogue.
          << "--", stream3::bits >> ->
            {:done, stream3};
          _ ->
            if String.match?(stream, ~r/\r\n\r\n/) do
              before_parse_headers(stream2)
            else
              # We don't have the full headers.
              {:more, stream2}
            end
        end
    end
  end

  # This indicates that there are no headers, so we can abort immediately.
  defp before_parse_headers(<< "\r\n\r\n", stream::bits >>), do: {:ok, [], stream}
  # There is a line break right after the boundary, skip it.
  defp before_parse_headers(<< "\r\n", stream::bits >>), do: parse_hd_name(stream, [], <<>>)

  defp parse_hd_name(<< ?:, rest::bits >>, h, acc), do: parse_hd_before_value(rest, h, acc)
  defp parse_hd_name(<< c, rest::bits >>, h, acc) when c in [?\s, ?\t], do: parse_hd_name_ws(rest, h, acc)
  defp parse_hd_name(<< c, rest::bits >>, h, acc), do: parse_hd_name(rest, h, <<acc::binary, lower(c)>>)

  defp parse_hd_name_ws(<< c, rest::bits >>, h, name) when c in [?\s, ?\t], do: parse_hd_name_ws(rest, h, name)
  defp parse_hd_name_ws(<< ?:, rest::bits >>, h, name), do: parse_hd_before_value(rest, h, name)

  defp parse_hd_before_value(<< ?\s, rest::bits >>, h, n), do: parse_hd_before_value(rest, h, n)
  defp parse_hd_before_value(<< ?\t, rest::bits >>, h, n), do: parse_hd_before_value(rest, h, n)
  defp parse_hd_before_value(buffer, h, n), do: parse_hd_value(buffer, h, n, <<>>)

  defp parse_hd_value(<< ?\r, rest::bits >>, headers, name, acc) do
    case rest do
      << "\n\r\n", rest2::bits >> -> {:ok, [{name, acc} | headers], rest2}
      << ?\n, c, rest2::bits >> when c in [?\s, ?\t] -> parse_hd_value(rest2, headers, name, acc)
      << ?\n, rest2::bits >> -> parse_hd_name(rest2, [{name, acc} | headers], <<>>)
    end
  end

  defp parse_hd_value(<< c, rest::bits >>, h, n, acc), do: parse_hd_value(rest, h, n, acc <> <<c>>)

  defp lower(c) do
    case c do
      ?A -> ?a
      ?B -> ?b
      ?C -> ?c
      ?D -> ?d
      ?E -> ?e
      ?F -> ?f
      ?G -> ?g
      ?H -> ?h
      ?I -> ?i
      ?J -> ?j
      ?K -> ?k
      ?L -> ?l
      ?M -> ?m
      ?N -> ?n
      ?O -> ?o
      ?P -> ?p
      ?Q -> ?q
      ?R -> ?r
      ?S -> ?s
      ?T -> ?t
      ?U -> ?u
      ?V -> ?v
      ?W -> ?w
      ?X -> ?x
      ?Y -> ?y
      ?Z -> ?z
      _ -> c
    end
  end

  @doc """
  Generate a new random boundary.

  The boundary generated has a low probability of ever appearing
  in the data.
  """
  @spec boundary() :: binary()
  def boundary(), do: :base64.encode(:crypto.strong_rand_bytes(48))

  @doc """
  Return the first part's head.

  This works exactly like the part/2 function except there is
  no leading \r\n. It's not required to use this function,
  just makes the output a little smaller and prettier.
  """
  @spec first_part(binary(), Plug.Conn.headers()) :: iodata()
  def first_part(boundary, headers), do: [<<"--">>, boundary, <<"\r\n">>, headers_to_iolist(headers)]

  @doc """
  Return a part's head.
  """
  @spec part(binary(), Plug.Conn.headers()) :: iodata()
  def part(boundary, headers), do: [<<"\r\n--">>, boundary, <<"\r\n">>, headers_to_iolist(headers)]

  defp headers_to_iolist(headers), do: List.foldr(headers, [], fn {n, v}, acc -> [<<"\r\n">>, v, <<": ">>, n | acc] end)

  @doc """
  Return the closing delimiter of the multipart message.
  """
  @spec close(binary()) :: iodata()
  def close(boundary), do: [<<"\r\n--">>, boundary, <<"--">>]

  @doc """
  Convenience function for extracting information from headers
  when parsing a multipart/form-data stream.
  """
  @spec form_data(Plug.Conn.headers()) :: {:data, binary()} | {:file, binary(), binary(), binary(), binary()}
  def form_data(headers) do
    {_, dispositionBin} = List.keyfind(headers, <<"content-disposition">>, 0)
    {<<"form-data">>, params} = parse_content_disposition(dispositionBin)
    {_, fieldName} = List.keyfind(params, <<"name">>, 0)
    case List.keyfind(params, <<"filename">>, 0) do
      false -> {:data, fieldName}
      {_, filename} ->
        type =
          case List.keyfind(headers, <<"content-type">>, 0) do
            false -> <<"text/plain">>
            {_, t} -> t
          end
        # @todo Turns out this is unnecessary per RFC7578 4.7.
        transferEncoding =
          case List.keyfind(headers, <<"content-transfer-encoding">>, 0) do
            false -> <<"7bit">>
            {_, tE} -> tE
          end
        {:file, fieldName, filename, type, transferEncoding}
    end
  end

  @doc """
  Parse an RFC 2183 content-disposition value.
  """
  @spec parse_content_disposition(binary()) :: {binary(), [{binary(), binary()}]}
  def parse_content_disposition(bin), do: parse_cd_type(bin, <<>>)

  defp parse_cd_type(<<>>, acc), do: {acc, []}
  defp parse_cd_type(<<c, rest::bits>>, acc) when c in [?;, ?\s, ?\t], do: {acc, parse_before_param(rest, [])}
  defp parse_cd_type(<<c, rest::bits>>, acc), do: parse_cd_type(rest, <<acc::binary, lower(c)>>)

  @doc """
  Parse an RFC 2045 content-transfer-encoding header.
  """
  @spec parse_content_transfer_encoding(binary()) :: binary()
  def parse_content_transfer_encoding(bin), do: lower(bin)

  @doc """
  Parse an RFC 2045 content-type header.
  """
  @spec parse_content_type(binary()) :: {binary(), binary(), [{binary(), binary()}]}
  def parse_content_type(bin), do: parse_ct_type(bin, <<>>)

  defp parse_ct_type(<<?/, rest::bits>>, acc), do: parse_ct_subtype(rest, acc, <<>>)
  defp parse_ct_type(<<c, rest::bits>>, acc), do: parse_ct_type(rest, <<acc::binary, lower(c)>>)

  defp parse_ct_subtype(<<>>, type, subtype) when subtype != <<>>, do: {type, subtype, []}
  defp parse_ct_subtype(<<c, rest::bits>>, type, acc) when c in [?;, ?\s, ?\t], do: {type, acc, parse_before_param(rest, [])}
  defp parse_ct_subtype(<<c, rest::bits>>, type, acc), do: parse_ct_subtype(rest, type, <<acc::binary, lower(c)>>)

  # Parse RFC 2045 parameters.
  defp parse_before_param(<<>>, params), do: Enum.reverse(params)
  defp parse_before_param(<<c, rest::bits>>, params) when c in [?;, ?\s, ?\t], do: parse_before_param(rest, params)
  defp parse_before_param(<<_, rest::bits>>, params), do: parse_param_name(rest, params, <<>>)

  defp parse_param_name(<<>>, params, acc), do: Enum.reverse([{acc, <<>>} | params])
  defp parse_param_name(<<?=, rest::bits>>, params, acc), do: parse_param_value(rest, params, acc)
  defp parse_param_name(<<c, rest::bits>>, params, acc), do: parse_param_name(rest, params, <<acc::binary, lower(c)>>)

  defp parse_param_value(<<>>, params, name), do: Enum.reverse([{name, <<>>} | params])
  defp parse_param_value(<<c, rest::bits>>, params, name) when c in [?;, ?\s, ?\t], do: parse_before_param(rest, [{name, <<>>} | params])
  defp parse_param_value(<<?", rest::bits>>, params, name), do: parse_param_quoted_value(rest, params, name, <<>>)
  defp parse_param_value(<<c, rest::bits>>, params, name), do: parse_param_value(rest, params, name, <<c>>)

  defp parse_param_value(<<>>, params, name, acc), do: Enum.reverse([{name, acc} | params])
  defp parse_param_value(<<c, rest::bits>>, params, name, acc) when c in [?;, ?\s, ?\t], do: parse_before_param(rest, [{name, acc} | params])
  defp parse_param_value(<<c, rest::bits>>, params, name, acc), do: parse_param_value(rest, params, name, <<acc::binary, c>>)

  # We expect a final ?" so no need to test for <<>>.
  defp parse_param_quoted_value(<<?\\, c, rest::bits>>, params, name, acc), do: parse_param_quoted_value(rest, params, name, <<acc::binary, c>>)
  defp parse_param_quoted_value(<<?", rest::bits>>, params, name, acc), do: parse_before_param(rest, [{name, acc} | params])
  defp parse_param_quoted_value(<<c, rest::bits>>, params, name, acc) when c != ?\r, do: parse_param_quoted_value(rest, params, name, <<acc::binary, c>>)
end
