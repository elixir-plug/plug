%% Copyright (c) 2014-2015, Loïc Hoguin <essen@ninenines.eu>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-module(plug_multipart).

%% Parsing.
-export([parse_headers/2]).
-export([parse_body/2]).

%% Building.
-export([boundary/0]).
-export([first_part/2]).
-export([part/2]).
-export([close/1]).

%% Headers.
-export([form_data/1]).
-export([parse_content_disposition/1]).
-export([parse_content_transfer_encoding/1]).
-export([parse_content_type/1]).

-type headers() :: [{iodata(), iodata()}].
-export_type([headers/0]).

-define(LC(C), case C of
  $A -> $a;
  $B -> $b;
  $C -> $c;
  $D -> $d;
  $E -> $e;
  $F -> $f;
  $G -> $g;
  $H -> $h;
  $I -> $i;
  $J -> $j;
  $K -> $k;
  $L -> $l;
  $M -> $m;
  $N -> $n;
  $O -> $o;
  $P -> $p;
  $Q -> $q;
  $R -> $r;
  $S -> $s;
  $T -> $t;
  $U -> $u;
  $V -> $v;
  $W -> $w;
  $X -> $x;
  $Y -> $y;
  $Z -> $z;
  _ -> C
end).

%% LOWER(Bin)
%%
%% Lowercase the entire binary string in a binary comprehension.

-define(LOWER(Bin), << << ?LC(C) >> || << C >> <= Bin >>).

%% LOWERCASE(Function, Rest, Acc, ...)
%%
%% To be included at the end of a case block.
%% Defined for up to 10 extra arguments.

-define(LOWER(Function, Rest, Acc), case C of
  $A -> Function(Rest, << Acc/binary, $a >>);
  $B -> Function(Rest, << Acc/binary, $b >>);
  $C -> Function(Rest, << Acc/binary, $c >>);
  $D -> Function(Rest, << Acc/binary, $d >>);
  $E -> Function(Rest, << Acc/binary, $e >>);
  $F -> Function(Rest, << Acc/binary, $f >>);
  $G -> Function(Rest, << Acc/binary, $g >>);
  $H -> Function(Rest, << Acc/binary, $h >>);
  $I -> Function(Rest, << Acc/binary, $i >>);
  $J -> Function(Rest, << Acc/binary, $j >>);
  $K -> Function(Rest, << Acc/binary, $k >>);
  $L -> Function(Rest, << Acc/binary, $l >>);
  $M -> Function(Rest, << Acc/binary, $m >>);
  $N -> Function(Rest, << Acc/binary, $n >>);
  $O -> Function(Rest, << Acc/binary, $o >>);
  $P -> Function(Rest, << Acc/binary, $p >>);
  $Q -> Function(Rest, << Acc/binary, $q >>);
  $R -> Function(Rest, << Acc/binary, $r >>);
  $S -> Function(Rest, << Acc/binary, $s >>);
  $T -> Function(Rest, << Acc/binary, $t >>);
  $U -> Function(Rest, << Acc/binary, $u >>);
  $V -> Function(Rest, << Acc/binary, $v >>);
  $W -> Function(Rest, << Acc/binary, $w >>);
  $X -> Function(Rest, << Acc/binary, $x >>);
  $Y -> Function(Rest, << Acc/binary, $y >>);
  $Z -> Function(Rest, << Acc/binary, $z >>);
  C -> Function(Rest, << Acc/binary, C >>)
end).

-define(LOWER(Function, Rest, A0, Acc), case C of
  $A -> Function(Rest, A0, << Acc/binary, $a >>);
  $B -> Function(Rest, A0, << Acc/binary, $b >>);
  $C -> Function(Rest, A0, << Acc/binary, $c >>);
  $D -> Function(Rest, A0, << Acc/binary, $d >>);
  $E -> Function(Rest, A0, << Acc/binary, $e >>);
  $F -> Function(Rest, A0, << Acc/binary, $f >>);
  $G -> Function(Rest, A0, << Acc/binary, $g >>);
  $H -> Function(Rest, A0, << Acc/binary, $h >>);
  $I -> Function(Rest, A0, << Acc/binary, $i >>);
  $J -> Function(Rest, A0, << Acc/binary, $j >>);
  $K -> Function(Rest, A0, << Acc/binary, $k >>);
  $L -> Function(Rest, A0, << Acc/binary, $l >>);
  $M -> Function(Rest, A0, << Acc/binary, $m >>);
  $N -> Function(Rest, A0, << Acc/binary, $n >>);
  $O -> Function(Rest, A0, << Acc/binary, $o >>);
  $P -> Function(Rest, A0, << Acc/binary, $p >>);
  $Q -> Function(Rest, A0, << Acc/binary, $q >>);
  $R -> Function(Rest, A0, << Acc/binary, $r >>);
  $S -> Function(Rest, A0, << Acc/binary, $s >>);
  $T -> Function(Rest, A0, << Acc/binary, $t >>);
  $U -> Function(Rest, A0, << Acc/binary, $u >>);
  $V -> Function(Rest, A0, << Acc/binary, $v >>);
  $W -> Function(Rest, A0, << Acc/binary, $w >>);
  $X -> Function(Rest, A0, << Acc/binary, $x >>);
  $Y -> Function(Rest, A0, << Acc/binary, $y >>);
  $Z -> Function(Rest, A0, << Acc/binary, $z >>);
  C -> Function(Rest, A0, << Acc/binary, C >>)
end).

%% Parsing.
%%
%% The multipart format is defined in RFC 2045.

%% @doc Parse the headers for the next multipart part.
%%
%% This function skips any preamble before the boundary.
%% The preamble may be retrieved using parse_body/2.
%%
%% This function will accept input of any size, it is
%% up to the caller to limit it if needed.

-spec parse_headers(binary(), binary())
  -> more | {more, binary()}
  | {ok, headers(), binary()}
  | {done, binary()}.
%% If the stream starts with the boundary we can make a few assumptions
%% and quickly figure out if we got the complete list of headers.
parse_headers(<< "--", Stream/bits >>, Boundary) ->
  BoundarySize = byte_size(Boundary),
  case Stream of
    %% Last boundary. Return the epilogue.
    << Boundary:BoundarySize/binary, "--", Stream2/bits >> ->
      {done, Stream2};
    << Boundary:BoundarySize/binary, Stream2/bits >> ->
      %% We have all the headers only if there is a \r\n\r\n
      %% somewhere in the data after the boundary.
      case binary:match(Stream2, <<"\r\n\r\n">>) of
        nomatch ->
          more;
        _ ->
          before_parse_headers(Stream2)
      end;
    %% If there isn't enough to represent Boundary \r\n\r\n
    %% then we definitely don't have all the headers.
    _ when byte_size(Stream) < byte_size(Boundary) + 4 ->
      more;
    %% Otherwise we have preamble data to skip.
    %% We still got rid of the first two misleading bytes.
    _ ->
      skip_preamble(Stream, Boundary)
  end;
%% Otherwise we have preamble data to skip.
parse_headers(Stream, Boundary) ->
  skip_preamble(Stream, Boundary).

%% We need to find the boundary and a \r\n\r\n after that.
%% Since the boundary isn't at the start, it must be right
%% after a \r\n too.
skip_preamble(Stream, Boundary) ->
  case binary:match(Stream, <<"\r\n--", Boundary/bits >>) of
    %% No boundary, need more data.
    nomatch ->
      %% We can safely skip the size of the stream
      %% minus the last 3 bytes which may be a partial boundary.
      SkipSize = byte_size(Stream) - 3,
      case SkipSize > 0 of
        false ->
          more;
        true ->
          << _:SkipSize/binary, Stream2/bits >> = Stream,
          {more, Stream2}
      end;
    {Start, Length} ->
      Start2 = Start + Length,
      << _:Start2/binary, Stream2/bits >> = Stream,
      case Stream2 of
        %% Last boundary. Return the epilogue.
        << "--", Stream3/bits >> ->
          {done, Stream3};
        _ ->
          case binary:match(Stream, <<"\r\n\r\n">>) of
            %% We don't have the full headers.
            nomatch ->
              {more, Stream2};
            _ ->
              before_parse_headers(Stream2)
          end
      end
  end.

before_parse_headers(<< "\r\n\r\n", Stream/bits >>) ->
  %% This indicates that there are no headers, so we can abort immediately.
  {ok, [], Stream};
before_parse_headers(<< "\r\n", Stream/bits >>) ->
  %% There is a line break right after the boundary, skip it.
  parse_hd_name(Stream, [], <<>>).

parse_hd_name(<< C, Rest/bits >>, H, SoFar) ->
  case C of
    $: -> parse_hd_before_value(Rest, H, SoFar);
    $\s -> parse_hd_name_ws(Rest, H, SoFar);
    $\t -> parse_hd_name_ws(Rest, H, SoFar);
    _ -> ?LOWER(parse_hd_name, Rest, H, SoFar)
  end.

parse_hd_name_ws(<< C, Rest/bits >>, H, Name) ->
  case C of
    $\s -> parse_hd_name_ws(Rest, H, Name);
    $\t -> parse_hd_name_ws(Rest, H, Name);
    $: -> parse_hd_before_value(Rest, H, Name)
  end.

parse_hd_before_value(<< $\s, Rest/bits >>, H, N) ->
  parse_hd_before_value(Rest, H, N);
parse_hd_before_value(<< $\t, Rest/bits >>, H, N) ->
  parse_hd_before_value(Rest, H, N);
parse_hd_before_value(Buffer, H, N) ->
  parse_hd_value(Buffer, H, N, <<>>).

parse_hd_value(<< $\r, Rest/bits >>, Headers, Name, SoFar) ->
  case Rest of
    << "\n\r\n", Rest2/bits >> ->
      {ok, [{Name, SoFar}|Headers], Rest2};
    << $\n, C, Rest2/bits >> when C =:= $\s; C =:= $\t ->
      parse_hd_value(Rest2, Headers, Name, SoFar);
    << $\n, Rest2/bits >> ->
      parse_hd_name(Rest2, [{Name, SoFar}|Headers], <<>>)
  end;
parse_hd_value(<< C, Rest/bits >>, H, N, SoFar) ->
  parse_hd_value(Rest, H, N, << SoFar/binary, C >>).

%% @doc Parse the body of the current multipart part.
%%
%% The body is everything until the next boundary.

-spec parse_body(binary(), binary())
  -> {ok, binary()} | {ok, binary(), binary()}
  | done | {done, binary()} | {done, binary(), binary()}.
parse_body(Stream, Boundary) ->
  BoundarySize = byte_size(Boundary),
  case Stream of
    << "--", Boundary:BoundarySize/binary, _/bits >> ->
      done;
    _ ->
      case binary:match(Stream, << "\r\n--", Boundary/bits >>) of
        %% No boundary, check for a possible partial at the end.
        %% Return more or less of the body depending on the result.
        nomatch ->
          StreamSize = byte_size(Stream),
          From = StreamSize - BoundarySize - 3,
          MatchOpts = if
            %% Binary too small to contain boundary, check it fully.
            From < 0 -> [];
            %% Optimize, only check the end of the binary.
            true -> [{scope, {From, StreamSize - From}}]
          end,
          case binary:match(Stream, <<"\r">>, MatchOpts) of
            nomatch ->
              {ok, Stream};
            {Pos, _} ->
              case Stream of
                << Body:Pos/binary >> ->
                  {ok, Body};
                << Body:Pos/binary, Rest/bits >> ->
                  {ok, Body, Rest}
              end
          end;
        %% Boundary found, this is the last chunk of the body.
        {Pos, _} ->
          case Stream of
            << Body:Pos/binary, "\r\n" >> ->
              {done, Body};
            << Body:Pos/binary, "\r\n", Rest/bits >> ->
              {done, Body, Rest};
            << Body:Pos/binary, Rest/bits >> ->
              {done, Body, Rest}
          end
      end
  end.

%% Building.

%% @doc Generate a new random boundary.
%%
%% The boundary generated has a low probability of ever appearing
%% in the data.

-spec boundary() -> binary().
boundary() ->
  base64:encode(crypto:strong_rand_bytes(48)).

%% @doc Return the first part's head.
%%
%% This works exactly like the part/2 function except there is
%% no leading \r\n. It's not required to use this function,
%% just makes the output a little smaller and prettier.

-spec first_part(binary(), headers()) -> iodata().
first_part(Boundary, Headers) ->
  [<<"--">>, Boundary, <<"\r\n">>, headers_to_iolist(Headers, [])].

%% @doc Return a part's head.

-spec part(binary(), headers()) -> iodata().
part(Boundary, Headers) ->
  [<<"\r\n--">>, Boundary, <<"\r\n">>, headers_to_iolist(Headers, [])].

headers_to_iolist([], Acc) ->
  lists:reverse([<<"\r\n">>|Acc]);
headers_to_iolist([{N, V}|Tail], Acc) ->
  %% We don't want to create a sublist so we list the
  %% values in reverse order so that it gets reversed properly.
  headers_to_iolist(Tail, [<<"\r\n">>, V, <<": ">>, N|Acc]).

%% @doc Return the closing delimiter of the multipart message.

-spec close(binary()) -> iodata().
close(Boundary) ->
  [<<"\r\n--">>, Boundary, <<"--">>].

%% Headers.

%% @doc Convenience function for extracting information from headers
%% when parsing a multipart/form-data stream.

-spec form_data(headers())
  -> {data, binary()}
  | {file, binary(), binary(), binary(), binary()}.
form_data(Headers) ->
  {_, DispositionBin} = lists:keyfind(<<"content-disposition">>, 1, Headers),
  {<<"form-data">>, Params} = parse_content_disposition(DispositionBin),
  {_, FieldName} = lists:keyfind(<<"name">>, 1, Params),
  case lists:keyfind(<<"filename">>, 1, Params) of
    false ->
      {data, FieldName};
    {_, Filename} ->
      Type = case lists:keyfind(<<"content-type">>, 1, Headers) of
        false -> <<"text/plain">>;
        {_, T} -> T
      end,
      %% @todo Turns out this is unnecessary per RFC7578 4.7.
      TransferEncoding = case lists:keyfind(
          <<"content-transfer-encoding">>, 1, Headers) of
        false -> <<"7bit">>;
        {_, TE} -> TE
      end,
      {file, FieldName, Filename, Type, TransferEncoding}
  end.

%% @doc Parse an RFC 2183 content-disposition value.

-spec parse_content_disposition(binary())
  -> {binary(), [{binary(), binary()}]}.
parse_content_disposition(Bin) ->
  parse_cd_type(Bin, <<>>).

parse_cd_type(<<>>, Acc) ->
  {Acc, []};
parse_cd_type(<< C, Rest/bits >>, Acc) ->
  case C of
    $; -> {Acc, parse_before_param(Rest, [])};
    $\s -> {Acc, parse_before_param(Rest, [])};
    $\t -> {Acc, parse_before_param(Rest, [])};
    _ -> ?LOWER(parse_cd_type, Rest, Acc)
  end.

%% @doc Parse an RFC 2045 content-transfer-encoding header.

-spec parse_content_transfer_encoding(binary()) -> binary().
parse_content_transfer_encoding(Bin) ->
  ?LOWER(Bin).

%% @doc Parse an RFC 2045 content-type header.

-spec parse_content_type(binary())
  -> {binary(), binary(), [{binary(), binary()}]}.
parse_content_type(Bin) ->
  parse_ct_type(Bin, <<>>).

parse_ct_type(<< C, Rest/bits >>, Acc) ->
  case C of
    $/ -> parse_ct_subtype(Rest, Acc, <<>>);
    _ -> ?LOWER(parse_ct_type, Rest, Acc)
  end.

parse_ct_subtype(<<>>, Type, Subtype) when Subtype =/= <<>> ->
  {Type, Subtype, []};
parse_ct_subtype(<< C, Rest/bits >>, Type, Acc) ->
  case C of
    $; -> {Type, Acc, parse_before_param(Rest, [])};
    $\s -> {Type, Acc, parse_before_param(Rest, [])};
    $\t -> {Type, Acc, parse_before_param(Rest, [])};
    _ -> ?LOWER(parse_ct_subtype, Rest, Type, Acc)
  end.

%% @doc Parse RFC 2045 parameters.

parse_before_param(<<>>, Params) ->
  lists:reverse(Params);
parse_before_param(<< C, Rest/bits >>, Params) ->
  case C of
    $; -> parse_before_param(Rest, Params);
    $\s -> parse_before_param(Rest, Params);
    $\t -> parse_before_param(Rest, Params);
    _ -> ?LOWER(parse_param_name, Rest, Params, <<>>)
  end.

parse_param_name(<<>>, Params, Acc) ->
  lists:reverse([{Acc, <<>>}|Params]);
parse_param_name(<< C, Rest/bits >>, Params, Acc) ->
  case C of
    $= -> parse_param_value(Rest, Params, Acc);
    _ -> ?LOWER(parse_param_name, Rest, Params, Acc)
  end.

parse_param_value(<<>>, Params, Name) ->
  lists:reverse([{Name, <<>>}|Params]);
parse_param_value(<< C, Rest/bits >>, Params, Name) ->
  case C of
    $" -> parse_param_quoted_value(Rest, Params, Name, <<>>);
    $; -> parse_before_param(Rest, [{Name, <<>>}|Params]);
    $\s -> parse_before_param(Rest, [{Name, <<>>}|Params]);
    $\t -> parse_before_param(Rest, [{Name, <<>>}|Params]);
    C -> parse_param_value(Rest, Params, Name, << C >>)
  end.

parse_param_value(<<>>, Params, Name, Acc) ->
  lists:reverse([{Name, Acc}|Params]);
parse_param_value(<< C, Rest/bits >>, Params, Name, Acc) ->
  case C of
    $; -> parse_before_param(Rest, [{Name, Acc}|Params]);
    $\s -> parse_before_param(Rest, [{Name, Acc}|Params]);
    $\t -> parse_before_param(Rest, [{Name, Acc}|Params]);
    C -> parse_param_value(Rest, Params, Name, << Acc/binary, C >>)
  end.

%% We expect a final $" so no need to test for <<>>.
parse_param_quoted_value(<< $\\, C, Rest/bits >>, Params, Name, Acc) ->
  parse_param_quoted_value(Rest, Params, Name, << Acc/binary, C >>);
parse_param_quoted_value(<< $", Rest/bits >>, Params, Name, Acc) ->
  parse_before_param(Rest, [{Name, Acc}|Params]);
parse_param_quoted_value(<< C, Rest/bits >>, Params, Name, Acc)
    when C =/= $\r ->
  parse_param_quoted_value(Rest, Params, Name, << Acc/binary, C >>).