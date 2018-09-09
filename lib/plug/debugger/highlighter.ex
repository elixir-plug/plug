defmodule Plug.Debugger.Highlighter do
  @moduledoc false
  alias Makeup.Lexers.ElixirLexer
  alias Makeup.Formatters.HTML.HTMLFormatter

  # -----------------------
  # Public API
  # -----------------------

  @doc """
  Outputs the CSS stylesheet for the classes used by Makeup
  """
  def style(class) do
    """
    .#{class} .hll {background-color: #ffffcc}
    .#{class} .bp {color: #3465a4; } /* :name_builtin_pseudo */
    .#{class} .c {color: #999999; } /* :comment */
    .#{class} .c1 {color: #999999; } /* :comment_single */
    .#{class} .ch {color: #999999; } /* :comment_hashbang */
    .#{class} .cm {color: #999999; } /* :comment_multiline */
    .#{class} .cp {color: #999999; } /* :comment_preproc */
    .#{class} .cpf {color: #999999; } /* :comment_preproc_file */
    .#{class} .cs {color: #999999; } /* :comment_special */
    .#{class} .dl {color: #4e9a06; } /* :string_delimiter */
    .#{class} .err {color: #a40000; border: #ef2929; } /* :error */
    .#{class} .fm {color: #000000; } /* :name_function_magic */
    .#{class} .g {color: #000000; } /* :generic */
    .#{class} .gd {color: #a40000; } /* :generic_deleted */
    .#{class} .ge {color: #000000; font-style: italic; } /* :generic_emph */
    .#{class} .gh {color: #000080; font-weight: bold; } /* :generic_heading */
    .#{class} .gi {color: #00A000; } /* :generic_inserted */
    .#{class} .go {color: #000000; font-style: italic; } /* :generic_output */
    .#{class} .gp {color: #999999; } /* :generic_prompt */
    .#{class} .gr {color: #ef2929; } /* :generic_error */
    .#{class} .gs {color: #000000; font-weight: bold; } /* :generic_strong */
    .#{class} .gt {color: #a40000; font-weight: bold; } /* :generic_traceback */
    .#{class} .gu {color: #800080; font-weight: bold; } /* :generic_subheading */
    .#{class} .il {color: #0000cf; font-weight: bold; } /* :number_integer_long */
    .#{class} .k {color: #204a87; } /* :keyword */
    .#{class} .kc {color: #204a87; } /* :keyword_constant */
    .#{class} .kd {color: #204a87; } /* :keyword_declaration */
    .#{class} .kn {color: #204a87; } /* :keyword_namespace */
    .#{class} .kp {color: #204a87; } /* :keyword_pseudo */
    .#{class} .kr {color: #204a87; } /* :keyword_reserved */
    .#{class} .kt {color: #204a87; } /* :keyword_type */
    .#{class} .l {color: #000000; } /* :literal */
    .#{class} .ld {color: #cc0000; } /* :literal_date */
    .#{class} .m {color: #2937ab; } /* :number */
    .#{class} .mb {color: #2937ab; } /* :number_bin */
    .#{class} .mf {color: #2937ab; } /* :number_float */
    .#{class} .mh {color: #2937ab; } /* :number_hex */
    .#{class} .mi {color: #2937ab; } /* :number_integer */
    .#{class} .mo {color: #2937ab; } /* :number_oct */
    .#{class} .n {color: #000000; } /* :name */
    .#{class} .na {color: #c4a000; } /* :name_attribute */
    .#{class} .nb {color: #204a87; } /* :name_builtin */
    .#{class} .nc {color: #0000cf; } /* :name_class */
    .#{class} .nd {color: #5c35cc; font-weight: bold; } /* :name_decorator */
    .#{class} .ne {color: #cc0000; font-weight: bold; } /* :name_exception */
    .#{class} .nf {color: #f57900; } /* :name_function */
    .#{class} .ni {color: #ce5c00; } /* :name_entity */
    .#{class} .nl {color: #f57900; } /* :name_label */
    .#{class} .nn {color: #000000; } /* :name_namespace */
    .#{class} .no {color: #c17d11; } /* :name_constant */
    .#{class} .nt {color: #204a87; font-weight: bold; } /* :name_tag */
    .#{class} .nv {color: #000000; } /* :name_variable */
    .#{class} .nx {color: #000000; } /* :name_other */
    .#{class} .o {color: #ce5c00; } /* :operator */
    .#{class} .ow {color: #204a87; } /* :operator_word */
    .#{class} .p {color: #000000; } /* :punctuation */
    .#{class} .py {color: #000000; } /* :name_property */
    .#{class} .s {color: #4e9a06; } /* :string */
    .#{class} .s1 {color: #4e9a06; } /* :string_single */
    .#{class} .s2 {color: #4e9a06; } /* :string_double */
    .#{class} .sa {color: #4e9a06; } /* :string_affix */
    .#{class} .sb {color: #4e9a06; } /* :string_backtick */
    .#{class} .sc {color: #4e9a06; } /* :string_char */
    .#{class} .sd {color: #8f5902; font-style: italic; } /* :string_doc */
    .#{class} .se {color: #204a87; } /* :string_escape */
    .#{class} .sh {color: #4e9a06; } /* :string_heredoc */
    .#{class} .si {color: #204a87; } /* :string_interpol */
    .#{class} .sr {color: #cc0000; } /* :string_regex */
    .#{class} .ss {color: #c17d11; } /* :string_symbol */
    .#{class} .sx {color: #4e9a06; } /* :string_other */
    .#{class} .sx {color: #4e9a06; } /* :string_sigil */
    .#{class} .vc {color: #000000; } /* :name_variable_class */
    .#{class} .vg {color: #000000; } /* :name_variable_global */
    .#{class} .vi {color: #000000; } /* :name_variable_instance */
    .#{class} .vm {color: #000000; } /* :name_variable_magic */
    .#{class} .x {color: #000000; } /* :other */
    """
  end

  @doc """
  Javascript to add at the end of the webpage so that matching delimiters
  are highlighted on mouseover.
  """
  def javascript() do
    HTMLFormatter.group_highlighter_javascript()
  end

  @doc """
  Highlights the arguments for a stack frame.

  Receives a list of elixir values and outputs a list of HTML strings.
  No need to care about splitting at linebreaks.
  """
  def highlight_args(args) do
    if Code.ensure_loaded?(ElixirLexer) do
      Enum.map(args, &highlight_arg/1)
    else
      plain_args(args)
    end
  end

  @doc """
  Highlights a sequence of lines of source code.

  Returns a list of highlighted lines in the format expected by `Plug.Debugger`.
  Must split tokens at linebreaks.
  """
  def highlight_snippet(lines, file) do
    case lexer_for_file(file) do
      _ -> lines
      ElixirLexer -> highlight_snippet_with_lexer(lines, ElixirLexer)
      _other -> plain_lines(lines)
    end
  end

  # ----------------------------
  # Private functions
  # ----------------------------

  # Highlighting function arguments:
  # --------------------------------

  # Escape arguments not meant to be highlighted,
  # so that they can be inserted in the HTML template
  defp plain_args(args) do
    Enum.map(args, fn arg -> arg |> inspect() |> escape_string() end)
  end

  # Highlight a list of arguments
  defp highlight_arg(arg) do
    # Makeup takes care of the escaping
    arg |> inspect() |> Makeup.highlight_inner_html()
  end

  # Highlight source lines
  # -----------------------------

  # Evaluates the maximum number of digits in a list of integers
  defp max_digits([]), do: 0

  defp max_digits(numbers) do
    numbers
    |> Enum.max()
    |> :math.log10()
    |> :math.ceil()
    |> round()
  end

  # Converts the line number into a string and pads it with wthitspace
  # so that it occupied the same space as the maximum number of digits
  # Number `5` might become `" 5"` or `"  5"`, depending
  # on the maximum line number
  defp pad_line_number(nr, length) do
    String.pad_leading(to_string(nr), length)
  end

  defp pad_lines(lines) do
    line_numbers = Enum.map(lines, fn {nr, _, _} -> nr end)
    length = max_digits(line_numbers)
    Enum.map(lines, fn {nr, line, highlight} ->
      {pad_line_number(nr, length), line, highlight}
    end)
  end

  # Stolen from `Plug.Debugger`
  defp escape_string(string) do
    string |> to_string() |> String.trim_trailing() |> Plug.HTML.html_escape()
  end

  defp escape_line({nr, line, highlighted}) do
    {nr, escape_string(line), highlighted}
  end

  defp escape_lines(lines) do
    Enum.map(lines, &escape_line/1)
  end

  defp plain_lines(lines) do
    lines
    |> pad_lines()
    |> escape_lines()
  end

  # Currently only an elixir lexer is supported
  defp lexer_for_file(file) do
    cond do
      String.ends_with?(file, ".ex") -> ElixirLexer
      String.ends_with?(file, ".exs") -> ElixirLexer
      :otherwise -> nil
    end
  end

  defp highlight_snippet_with_lexer(lines, lexer) do
    if Code.ensure_loaded?(lexer) do
      # Unzip the 3-tuples
      line_numbers = Enum.map(lines, fn {nr, _, _} -> nr end)
      text_lines = Enum.map(lines, fn {_, line, _} -> line end)
      # `highlight` here has nothing to do with syntax highlighting;
      # It marks the lines we mush highlight becuase that's where the error occured.
      highlight = Enum.map(lines, fn {_, _, highlight} -> highlight end)
      # Join the lines we're about to highlight
      # Highlighting will be more precise that way.
      # Highlighting will still be unreliable if there is a token that spans too many lines,
      # for example, a long heredoc.
      # This is an argument for highlighting the whole file and extracting the interesting lines later.
      # TODO: should we do this?
      text = Enum.join(text_lines, "")
      # Get a list of tokens. Tokens may span more than one line.
      tokens = lexer.lex(text)
      # We must split the list of tokens into a list of lists,
      # splitting a token in several parts if needed.
      token_lines = split_into_lines(tokens)
      # Finally, render the lines into HTML.
      # The HTML is already escaped, which means we don't escape it again in the template
      html_lines = Enum.map(token_lines, fn line -> token_line_to_html(line) end)
      debugger_lines = Enum.zip([line_numbers, html_lines, highlight])
      pad_lines(debugger_lines)
    else
      plain_lines(lines)
    end
  end

  defp token_line_to_html(tokens) do
    html =
      tokens
      |> Enum.map(fn token -> HTMLFormatter.format_token(token) end)
      |> Enum.join("")

    html
  end

  # Splits a list of tokens into lines.
  # If necessary, will split a token on linebreaks.
  defp split_into_lines(tokens) do
    {lines, last_line} =
      Enum.reduce tokens, {[], []}, (fn {ttype, meta, value} = tok, {lines, line} ->
        text = value |> escape() |> IO.iodata_to_binary()
        case String.split(text, "\n") do
          [_] -> {lines, [tok | line]}
          [part | parts] ->
            first_line = [{ttype, meta, part} | line] |> :lists.reverse

            all_but_last_line =
              parts
              |> Enum.slice(0..-2)
              |> Enum.map(fn tok_text -> [{ttype, meta, tok_text}] end)
              |> :lists.reverse

            last_line_text = Enum.at(parts, -1)
            last_line = [{ttype, meta, Enum.at(parts, -1)}]

            case last_line_text do
              "" -> {all_but_last_line ++ [first_line | lines], []}
              _ -> {all_but_last_line ++ [first_line | lines], last_line}
            end

        end
      end)

    :lists.reverse([last_line | lines])
  end

  defp escape(iodata) when is_list(iodata) do
    iodata
    |> :lists.flatten()
    |> Enum.map(&escape_for/1)
  end

  defp escape(other) when is_binary(other) do
    Plug.HTML.html_escape(other)
  end

  defp escape(c) when is_integer(c) do
    [escape_for(c)]
  end

  defp escape(other) do
    raise "Found `#{inspect(other)}` inside what should be an iolist"
  end

  defp escape_for(?&), do: "&amp;"

  defp escape_for(?<), do: "&lt;"

  defp escape_for(?>), do: "&gt;"

  defp escape_for(?"), do: "&quot;"

  defp escape_for(?'), do: "&#39;"

  defp escape_for(c) when is_integer(c) and c <= 127, do: c

  defp escape_for(c) when is_integer(c) and c > 128, do: << c :: utf8 >>

  defp escape_for(string) when is_binary(string) do
    Plug.HTML.html_escape(string)
  end
end