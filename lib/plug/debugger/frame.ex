defmodule Plug.Debugger.Frame do
  @moduledoc """
  Struct that holds debug data used in the default debugger template.

  This module defines a struct and only one public function generate_frames/3.
  Used with the default debugger template at `lib/plug/debugger/template.eex`.
  """

  defstruct [:module, :function, :file, :line, :context, :index, :snippet]

  alias Plug.Debugger.Frame

  @doc """
  Generates multiple Frame structs that will be used in the debugger template.
  """
  def generate_frames(stacktrace, root, sources) do
    sources = Path.wildcard(sources)

    Enum.map_reduce(stacktrace, 0, fn(trace_item, index) ->
      each_frame(trace_item, index, root, sources)
    end) |> elem(0)
  end

  defp each_frame({ module, function, args_or_arity, opts }, index, root, sources) do
    { mod, fun } = mod_fun(module, function, args_or_arity)
    { file, line } = { to_string(opts[:file] || "nofile"), opts[:line] }
    { relative, context, snippet } = file_context(file, line, root, sources)

    { %Frame{
        module: mod,
        function: fun,
        file: relative,
        line: line,
        context: context,
        snippet: snippet,
        index: index
      }, index + 1 }
  end

  defp mod_fun(module, :__MODULE__, 0) do
    { inspect(module) <> " (module)", nil }
  end

  defp mod_fun(_module, :__MODULE__, 2) do
    { "(module)", nil }
  end

  defp mod_fun(_module, :__FILE__, 2) do
    { "(file)", nil }
  end

  defp mod_fun(module, fun, args_or_arity) do
    { inspect(module), "#{fun}/#{arity(args_or_arity)}" }
  end

  defp arity(args) when is_list(args), do: length(args)
  defp arity(arity) when is_integer(arity), do: arity

  @radius 5

  defp file_context(original, line, root, sources) do
    file = Path.relative_to(original, root)

    if Enum.member?(sources, file) do
      context = :plug
      snippet = is_integer(line) and extract_snippet(file, line)
    else
      context = :all
    end

    { file, context, snippet }
  end

  defp extract_snippet(original, line) do
    if File.regular?(original) do
      to_discard = max(line - @radius - 1, 0)
      lines = File.stream!(original) |> Stream.take(line + 5) |> Stream.drop(to_discard)

      { first_five, lines } = Enum.split(lines, line - to_discard - 1)
      first_five = with_line_number first_five, to_discard + 1, false

      { center, last_five } = Enum.split(lines, 1)
      center = with_line_number center, line, true
      last_five = with_line_number last_five, line + 1, false

      first_five ++ center ++ last_five
    end
  end

  defp with_line_number(lines, initial, highlight) do
    Enum.map_reduce(lines, initial, fn(line, acc) ->
      { { acc, line, highlight }, acc + 1 }
    end) |> elem(0)
  end
end
