defmodule Plug.Router.InvalidSpecError do
  defexception message: "invalid route specification"
end

defmodule Plug.Router.MalformedURIError do
  defexception message: "malformed URI", plug_status: 400
end

defmodule Plug.Router.Utils do
  @moduledoc false

  @doc """
  Decodes path information for dispatching.
  """
  def decode_path_info!(conn) do
    # TODO: Remove rescue as this can't fail from Elixir v1.13
    try do
      Enum.map(conn.path_info, &URI.decode/1)
    rescue
      e in ArgumentError ->
        reason = %Plug.Router.MalformedURIError{message: e.message}
        Plug.Conn.WrapperError.reraise(conn, :error, reason, __STACKTRACE__)
    end
  end

  @doc """
  Converts a given method to its connection representation.

  The request method is stored in the `Plug.Conn` struct as an uppercase string
  (like `"GET"` or `"POST"`). This function converts `method` to that
  representation.

  ## Examples

      iex> Plug.Router.Utils.normalize_method(:get)
      "GET"

  """
  def normalize_method(method) do
    method |> to_string |> String.upcase()
  end

  @doc ~S"""
  Builds the pattern that will be used to match against the request's host
  (provided via the `:host`) option.

  If `host` is `nil`, a wildcard match (`_`) will be returned. If `host` ends
  with a dot, a match like `"host." <> _` will be returned.

  ## Examples

      iex> Plug.Router.Utils.build_host_match(nil)
      {:_, [], Plug.Router.Utils}

      iex> Plug.Router.Utils.build_host_match("foo.com")
      "foo.com"

      iex> "api." |> Plug.Router.Utils.build_host_match() |> Macro.to_string()
      "\"api.\" <> _"

  """
  def build_host_match(host) do
    cond do
      is_nil(host) -> quote do: _
      String.last(host) == "." -> quote do: unquote(host) <> _
      is_binary(host) -> host
    end
  end

  @doc """
  Generates a representation that will only match routes
  according to the given `spec`.

  If a non-binary spec is given, it is assumed to be
  custom match arguments and they are simply returned.

  ## Examples

      iex> Plug.Router.Utils.build_path_match("/foo/:id")
      {[:id], ["foo", {:id, [], nil}]}

  """
  def build_path_match(path, context \\ nil) when is_binary(path) do
    case build_path_clause(path, true, context) do
      {params, match, true, _post_match} ->
        {Enum.map(params, &String.to_atom(&1)), match}

      {_, _, _, _} ->
        raise Plug.Router.InvalidSpecError,
              "invalid dynamic path. Only letters, numbers, and underscore are allowed after : in " <>
                inspect(path)
    end
  end

  @doc """
  Builds a list of path param names and var match pairs.

  This is used to build parameter maps from existing variables.
  Excludes variables with underscore.

  ## Examples

      iex> Plug.Router.Utils.build_path_params_match(["id"])
      [{"id", {:id, [], nil}}]
      iex> Plug.Router.Utils.build_path_params_match(["_id"])
      []

      iex> Plug.Router.Utils.build_path_params_match([:id])
      [{"id", {:id, [], nil}}]
      iex> Plug.Router.Utils.build_path_params_match([:_id])
      []

  """
  # TODO: Make me private in Plug v2.0
  def build_path_params_match(params, context \\ nil)

  def build_path_params_match([param | _] = params, context) when is_binary(param) do
    params
    |> Enum.reject(&match?("_" <> _, &1))
    |> Enum.map(&{&1, Macro.var(String.to_atom(&1), context)})
  end

  def build_path_params_match([param | _] = params, context) when is_atom(param) do
    params
    |> Enum.map(&{Atom.to_string(&1), Macro.var(&1, context)})
    |> Enum.reject(&match?({"_" <> _var, _macro}, &1))
  end

  def build_path_params_match([], _context) do
    []
  end

  @doc """
  Builds a clause with match, guards, and post matches,
  including the known parameters.
  """
  def build_path_clause(path, guard, context \\ nil) when is_binary(path) do
    compiled = :binary.compile_pattern([":", "*"])

    {params, match, guards, post_match} =
      path
      |> split()
      |> build_path_clause([], [], [], [], context, compiled)

    if guard != true and guards != [] do
      raise ArgumentError, "cannot use \"when\" guards in route when using suffix matches"
    end

    params = params |> Enum.uniq() |> Enum.reverse()
    guards = Enum.reduce(guards, guard, &quote(do: unquote(&1) and unquote(&2)))
    {params, match, guards, post_match}
  end

  defp build_path_clause([segment | rest], params, match, guards, post_match, context, compiled) do
    case :binary.matches(segment, compiled) do
      [] ->
        build_path_clause(rest, params, [segment | match], guards, post_match, context, compiled)

      [{prefix_size, _}] ->
        suffix_size = byte_size(segment) - prefix_size - 1
        <<prefix::binary-size(prefix_size), char, suffix::binary-size(suffix_size)>> = segment
        {param, suffix} = parse_suffix(suffix)
        params = [param | params]
        var = Macro.var(String.to_atom(param), context)

        case char do
          ?* when suffix != "" ->
            raise Plug.Router.InvalidSpecError,
                  "globs (*var) cannot be followed by suffixes, got: #{inspect(segment)}"

          ?* when rest != [] ->
            raise Plug.Router.InvalidSpecError,
                  "globs (*var) must always be in the last path, got glob in: #{inspect(segment)}"

          ?* ->
            submatch =
              if prefix != "" do
                IO.warn("""
                doing a prefix match with globs is deprecated, invalid segment #{inspect(segment)}.

                You can either replace by a single segment match:

                    /foo/bar-:var

                Or by mixing single segment match with globs:

                    /foo/bar-:var/*rest
                """)

                quote do: [unquote(prefix) <> _ | _] = unquote(var)
              else
                var
              end

            match =
              case match do
                [] ->
                  submatch

                [last | match] ->
                  Enum.reverse([quote(do: unquote(last) | unquote(submatch)) | match])
              end

            {params, match, guards, post_match}

          ?: ->
            match =
              if prefix == "",
                do: [var | match],
                else: [quote(do: unquote(prefix) <> unquote(var)) | match]

            {post_match, guards} =
              if suffix == "" do
                {post_match, guards}
              else
                guard =
                  quote do
                    binary_part(
                      unquote(var),
                      byte_size(unquote(var)) - unquote(byte_size(suffix)),
                      unquote(byte_size(suffix))
                    ) == unquote(suffix)
                  end

                trim =
                  quote do
                    unquote(var) = String.trim_trailing(unquote(var), unquote(suffix))
                  end

                {[trim | post_match], [guard | guards]}
              end

            build_path_clause(rest, params, match, guards, post_match, context, compiled)
        end

      [_ | _] ->
        raise Plug.Router.InvalidSpecError,
              "only one dynamic entry (:var or *glob) per path segment is allowed, got: " <>
                inspect(segment)
    end
  end

  defp build_path_clause([], params, match, guards, post_match, _context, _compiled) do
    {params, Enum.reverse(match), guards, post_match}
  end

  defp parse_suffix(<<h, t::binary>>) when h in ?a..?z or h == ?_,
    do: parse_suffix(t, <<h>>)

  defp parse_suffix(suffix) do
    raise Plug.Router.InvalidSpecError,
          "invalid dynamic path. The characters : and * must be immediately followed by " <>
            "lowercase letters or underscore, got: :#{suffix}"
  end

  defp parse_suffix(<<h, t::binary>>, acc)
       when h in ?a..?z or h in ?A..?Z or h in ?0..?9 or h == ?_,
       do: parse_suffix(t, <<acc::binary, h>>)

  defp parse_suffix(rest, acc),
    do: {acc, rest}

  @doc """
  Splits the given path into several segments.
  It ignores both leading and trailing slashes in the path.

  ## Examples

      iex> Plug.Router.Utils.split("/foo/bar")
      ["foo", "bar"]

      iex> Plug.Router.Utils.split("/:id/*")
      [":id", "*"]

      iex> Plug.Router.Utils.split("/foo//*_bar")
      ["foo", "*_bar"]

  """
  def split(bin) do
    for segment <- String.split(bin, "/"), segment != "", do: segment
  end

  @deprecated "Use Plug.forward/4 instead"
  defdelegate forward(conn, new_path, target, opts), to: Plug
end
