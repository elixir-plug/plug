defexception Plug.Router.InvalidSpecError, message: "invalid route specification"

defmodule Plug.Router.Utils do
  @moduledoc false

  @doc """
  Convert a given method to its connection representation.

  ## Examples

      iex> Plug.Router.Utils.normalize_method(:get)
      "GET"

  """
  def normalize_method(method) do
    String.upcase(to_string(method))
  end

  @doc """
  Generates a representation that will only match routes
  according to the given `spec`.

  If a non-binary spec is given, it is assumed to be
  custom match arguments and they are simply returned.

  ## Examples

      iex> Plug.Router.Utils.build_match("/foo/:id")
      { [:id], ["foo", { :id, [], nil }] }

  """
  def build_match(spec) when is_binary(spec) do
    build_match split(spec), [], []
  end

  def build_match(spec) do
    { [], spec }
  end

  @doc """
  Forwards requests to another Plug at a new path.

  """
  def forward(Plug.Conn[path_info: path, script_name: script] = conn, new_path, options) do
    target = options[:to]
    {base, ^new_path} = Enum.split(path, length(path) - length(new_path))

    conn = conn.update(path_info: new_path, script_name: base ++ script) |> target.call([])

    conn.update(path_info: path, script_name: script)
  end

  @doc """
  Splits the given path into several segments.
  It ignores both leading and trailing slashes in the path.

  ## Examples

      iex> Plug.Router.Utils.split("/foo/bar")
      ["foo", "bar"]

  """
  def split(bin) do
    lc segment inlist String.split(bin, "/"), segment != "", do: segment
  end

  ## Helpers

  # Loops each segment checking for matches.

  defp build_match([h|t], vars, acc) do
    handle_segment_match segment_match(h, ""), t, vars, acc
  end

  defp build_match([], vars, acc) do
    { vars |> Enum.uniq |> Enum.reverse, Enum.reverse(acc) }
  end

  # Handle each segment match. They can either be a
  # :literal ("foo"), an identifier (":bar") or a glob ("*path")

  defp handle_segment_match({ :literal, literal }, t, vars, acc) do
    build_match t, vars, [literal|acc]
  end

  defp handle_segment_match({ :identifier, identifier, expr }, t, vars, acc) do
    build_match t, [identifier|vars], [expr|acc]
  end

  defp handle_segment_match({ :glob, identifier, expr }, t, vars, acc) do
    if t != [] do
      raise Plug.Router.InvalidSpecError, message: "cannot have a *glob followed by other segments"
    end

    case acc do
      [hs|ts] ->
        acc = [{ :|, [], [hs, expr] } | ts]
        build_match([], [identifier|vars], acc)
      _ ->
        { vars, expr } = build_match([], [identifier|vars], [expr])
        { vars, hd(expr) }
    end
  end

  # In a given segment, checks if there is a match.

  @underscore { :_, [], nil }

  defp segment_match(":" <> argument, buffer) do
    identifier = binary_to_identifier(":", argument)
    expr = quote_if_buffer identifier, buffer, fn var ->
      quote do: unquote(buffer) <> unquote(var)
    end
    { :identifier, identifier, expr }
  end

  defp segment_match("*" <> argument, buffer) do
    identifier = binary_to_identifier("*", argument)
    expr = quote_if_buffer identifier, buffer, fn var ->
      quote do: [unquote(buffer) <> unquote(@underscore)|unquote(@underscore)] = unquote(var)
    end
    { :glob, identifier, expr }
  end

  defp segment_match(<<h, t::binary>>, buffer) do
    segment_match t, buffer <> <<h>>
  end

  defp segment_match(<<>>, buffer) do
    { :literal, buffer }
  end

  defp quote_if_buffer(identifier, "", _fun) do
    { identifier, [], nil }
  end

  defp quote_if_buffer(identifier, _buffer, fun) do
    fun.({ identifier, [], nil })
  end

  defp binary_to_identifier(prefix, "") do
    raise Plug.Router.InvalidSpecError, message: "#{prefix} must be followed by lowercase letters in routes"
  end

  defp binary_to_identifier(_, binary) do
    binary_to_atom(binary)
  end
end
