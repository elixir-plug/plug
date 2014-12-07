defmodule Plug.Router.InvalidSpecError do
  defexception message: "invalid route specification"
end

defmodule Plug.Router.Utils do
  @moduledoc false

  @doc """
  Convert a given method to its connection representation.

  ## Examples

      iex> Plug.Router.Utils.normalize_method(:get)
      "GET"

  """
  def normalize_method(method) do
    method |> to_string |> String.upcase
  end

  @doc """
  Build the pattern that will be used to match against the request's host
  (provided via the `:host`) option.

  ## Examples

      iex> Plug.Router.Utils.build_host_match(nil)
      {:_, [], Plug.Router.Utils}

      iex> Plug.Router.Utils.build_host_match("foo.com")
      "foo.com"

  """
  def build_host_match(host) do
    cond do
      is_nil host              -> quote do: _
      String.last(host) == "." -> quote do: unquote(host) <> _
      is_binary host           -> host
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
  def build_path_match(spec, context \\ nil) when is_binary(spec) do
    build_path_match split(spec), context, [], []
  end

  @doc """
  Forwards requests to another Plug at a new path.
  """
  def forward(%Plug.Conn{path_info: path, script_name: script} = conn, new_path, target, opts) do
    {base, ^new_path} = Enum.split(path, length(path) - length(new_path))
    conn = %{conn | path_info: new_path, script_name: base ++ script} |> target.call(opts)
    %{conn | path_info: path, script_name: script}
  end

  @doc """
  Splits the given path into several segments.
  It ignores both leading and trailing slashes in the path.

  ## Examples

      iex> Plug.Router.Utils.split("/foo/bar")
      ["foo", "bar"]

  """
  def split(bin) do
    for segment <- String.split(bin, "/"), segment != "", do: segment
  end

  ## Helpers

  # Loops each segment checking for matches.

  defp build_path_match([h|t], context, vars, acc) do
    handle_segment_match segment_match(h, "", context), t, context, vars, acc
  end

  defp build_path_match([], _context, vars, acc) do
    {vars |> Enum.uniq |> Enum.reverse, Enum.reverse(acc)}
  end

  # Handle each segment match. They can either be a
  # :literal ("foo"), an identifier (":bar") or a glob ("*path")

  defp handle_segment_match({:literal, literal}, t, context, vars, acc) do
    build_path_match t, context, vars, [literal|acc]
  end

  defp handle_segment_match({:identifier, identifier, expr}, t, context, vars, acc) do
    build_path_match t, context, [identifier|vars], [expr|acc]
  end

  defp handle_segment_match({:glob, identifier, expr}, t, context, vars, acc) do
    if t != [] do
      raise Plug.Router.InvalidSpecError, message: "cannot have a *glob followed by other segments"
    end

    case acc do
      [hs|ts] ->
        acc = [{:|, [], [hs, expr]} | ts]
        build_path_match([], context, [identifier|vars], acc)
      _ ->
        {vars, expr} = build_path_match([], context, [identifier|vars], [expr])
        {vars, hd(expr)}
    end
  end

  # In a given segment, checks if there is a match.

  @underscore {:_, [], nil}

  defp segment_match(":" <> argument, buffer, context) do
    identifier = binary_to_identifier(":", argument)
    expr = quote_if_buffer identifier, buffer, context, fn var ->
      quote do: unquote(buffer) <> unquote(var)
    end
    {:identifier, identifier, expr}
  end

  defp segment_match("*" <> argument, buffer, context) do
    underscore = {:_, [], context}
    identifier = binary_to_identifier("*", argument)
    expr = quote_if_buffer identifier, buffer, context, fn var ->
      quote do: [unquote(buffer) <> unquote(underscore)|unquote(underscore)] = unquote(var)
    end
    {:glob, identifier, expr}
  end

  defp segment_match(<<h, t::binary>>, buffer, context) do
    segment_match t, buffer <> <<h>>, context
  end

  defp segment_match(<<>>, buffer, _context) do
    {:literal, buffer}
  end

  defp quote_if_buffer(identifier, "", context, _fun) do
    {identifier, [], context}
  end

  defp quote_if_buffer(identifier, _buffer, context, fun) do
    fun.({identifier, [], context})
  end

  defp binary_to_identifier(prefix, <<letter, _::binary>> = binary)
      when letter in ?a..?z or letter == ?_ do
    if binary =~ ~r/^\w+$/ do
      String.to_atom(binary)
    else
      raise Plug.Router.InvalidSpecError,
        message: "#{prefix}identifier in routes must be made of letters, numbers and underscore"
    end
  end

  defp binary_to_identifier(prefix, _) do
    raise Plug.Router.InvalidSpecError,
      message: "#{prefix} in routes must be followed by lowercase letters or underscore"
  end
end
