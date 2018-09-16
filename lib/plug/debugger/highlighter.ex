defmodule Plug.Debugger.Highlighter do
  @moduledoc false
  alias Makeup.Lexer
  alias Makeup.Lexers.ElixirLexer
  alias Makeup.Formatters.HTML.HTMLFormatter

  # -----------------------
  # Public API
  # -----------------------

  # The Highlighter functions detect if the appropriate lexer is available.
  # If the lexer is not available, the functions render the text as plaintext.
  # However, for testing purposes, it might be useful to render text as plaintext
  # even though the lexer is available.
  #
  # To help with testing, the Highlighter provides a way to turn off
  # syntax highlighting even when the lexer is available.

  @doc """
  Manually deactivate the highlighter.

  To temporarily deactivate the highlighter,
  you should use `Plug.Debugger.Highlighter.with_inactive_highlighter/1` instead.
  """
  def deactivate() do
    set_activation_state(false)
  end

  @doc """
  Manually activate the highlighter.

  To temporarily activate the highlighter,
  you should use `Plug.Debugger.Highlighter.with_active_highlighter/1` instead.
  """
  def activate() do
    set_activation_state(true)
  end

  @doc """
  Runs a given function with the highlighter active  (the default).

  After running the function, the highlighter is reverted to its previous state.
  Even if the function raises an error, the highlighter is reverted to its previous state
  and the error is propagated.

  If you want to do something while ensuring the Highlighter is active,
  you should probably use this function.
  """
  def with_active_highlighter(fun) do
    with_highlighter_activation_set_to(true, fun)
  end

  @doc """
  Runs a given function with the highlighter deactivated
  (simulates a situation in which the lexer is not available).

  After running the function, the highlighter is reverted to its previous state.
  Even if the function raises an error, the highlighter is reverted to its previous state
  and the error is propagated.

  If you want to do something while the Highlighter is deactivated,
  you should probably use this function.
  """
  def with_inactive_highlighter(fun) do
    with_highlighter_activation_set_to(false, fun)
  end

  @doc """
  Checks if the highlighter is active.

  The highlighter is only inactive when someone has explicitly deactivated it.
  Otherwise, it's active.
  """
  def is_active?() do
    Application.get_env(:plug, :use_syntax_highlighting_in_debugger) != false
  end

  @doc """
  Outputs the CSS stylesheet for the classes used by Makeup.
  This theme isn't included in Makeup yet, so we'll include it here.
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
  def highlight_args(nil), do: nil

  def highlight_args(args) do
    # Arguments should be highlighted as Elixir values, not Erlang terms
    # Test if:
    #   1. The elixir lexer is loaded
    #      The `args` are always highlighted using the elixir lexer,
    #      even if they come from an erlang file.
    #   2. The highlighter is active (we might want to turn it off for tests)
    if Code.ensure_loaded?(ElixirLexer) && is_active?() do
      Enum.map(args, &highlight_arg/1)
    else
      plain_args(args)
    end
  end

  @doc """
  Returns a snippet, which may or may not be highlighted.

  In any case, the snipppet is already escaped.
  It should not be escaped again before being added to the template.
  """
  def get_snippet(file, line) do
    if File.regular?(file) and is_integer(line) do
      lexer = lexer_for_file(file)
      # Test if:
      #   1. The lexer picked from the file name is not `nil`
      #   2. The lexer is loaded
      #   3. The highlighter is active (we might want to turn it off for tests)
      if lexer && Code.ensure_loaded?(lexer) && is_active?() do
        get_highlighted_snippet(file, lexer, line)
      else
        get_plain_snippet(file, line)
      end
    end
  end

  # -------------------------
  # Private functions
  # -------------------------

  # Helpers for `get_snippet/2`:
  # ----------------------------

  @radius 5

  # 1. First branch: the `ElixirLexer` is available
  # -----------------------------------------------
  # Lines will need to be lexed and formatted.
  # The HTML formatter already takes care of HTML escaping,
  # so they don't need to be escaped again.

  defp get_highlighted_snippet(file, lexer, line) do
    to_discard = max(line - @radius - 1, 0)
    # We use `Enum` and not `Stream` because we already
    lines =
      highlight_file(file, lexer)
      |> Enum.take(line + 5)
      |> Enum.drop(to_discard)

    {first_five, lines} = Enum.split(lines, line - to_discard - 1)
    first_five = with_line_number(first_five, to_discard + 1, false)

    {center, last_five} = Enum.split(lines, 1)
    center = with_line_number(center, line, true)
    last_five = with_line_number(last_five, line + 1, false)

    lines_to_format = first_five ++ center ++ last_five

    lines_to_format |> format_lines() |> pad_lines()
  end

  # Highlight the whole file and split it into lines.
  # We need to highlight the whole file becuase the lexer might highlight
  # the file incorrectly if it doesn't take into account the whole context.
  # For example:1
  #
  #     defmodule WilRaiseAnError do
  #       @doc """
  #       Blah blah blah,
  #       blah blah blah, Blah! # <- section starts here
  #       Blah blah blah,
  #       blah blah blah, Blah!
  #       Some docs even more docs etc
  #       """
  #       def f(x) do
  #         x/0
  #       end
  #     end
  #
  # In the above module, the highlighted would highlight the source incorrectly
  # if given only the lines around the error as context.
  # Highlighting the whole file decreases performance, of course, but because
  # the debugger is meant to be used in dev only, the tradeoff is accceptable.
  def highlight_file(file, lexer) do
    contents = File.read!(file)
    tokens = lexer.lex(contents)
    Lexer.split_into_lines(tokens)
  end

  defp format_lines(lines) do
    Enum.map(lines, &format_line/1)
  end

  defp format_line({nr, tokens, highlight}) do
    html =
      tokens
      |> Enum.map(fn token -> HTMLFormatter.format_token(token) end)
      |> Enum.join("")

    {nr, html, highlight}
  end

  defp lexer_for_file(file) do
    cond do
      String.ends_with?(file, ".exs") -> ElixirLexer
      String.ends_with?(file, ".ex") -> ElixirLexer
      true -> nil
    end
  end

  # 2. Second branch: the `ElixirLexer` is not available
  # ----------------------------------------------------
  # Lines will be rendered as plain text.
  # The are not lexed or formatted, but they need to be escaped.

  defp get_plain_snippet(file, line) do
    if File.regular?(file) and is_integer(line) do
      to_discard = max(line - @radius - 1, 0)
      lines = File.stream!(file) |> Stream.take(line + 5) |> Stream.drop(to_discard)

      {first_five, lines} = Enum.split(lines, line - to_discard - 1)
      first_five = with_line_number(first_five, to_discard + 1, false)

      {center, last_five} = Enum.split(lines, 1)
      center = with_line_number(center, line, true)
      last_five = with_line_number(last_five, line + 1, false)

      unescaped_lines = first_five ++ center ++ last_five

      unescaped_lines |> escape_plain_lines() |> pad_lines()
    end
  end

  defp escape_plain_lines(lines) do
    Enum.map(lines, fn {nr, line, highlight} ->
      {nr, line |> String.trim_trailing() |> Plug.HTML.html_escape(), highlight}
    end)
  end

  # 3. Helper functions common to both branches

  defp with_line_number(lines, initial, highlight) do
    lines
    |> Enum.map_reduce(initial, fn line, acc -> {{acc, line, highlight}, acc + 1} end)
    |> elem(0)
  end

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

  # Get the lexer from the filename

  # Highlighting function arguments:
  # --------------------------------

  # Escape arguments not meant to be highlighted,
  # so that they can be inserted in the HTML template
  defp plain_args(args) do
    Enum.map(args, fn arg ->
      arg
      |> inspect()
      |> String.trim_trailing()
      |> Plug.HTML.html_escape()
    end)
  end

  # Highlight a list of arguments
  # Makeup takes care of the escaping
  defp highlight_arg(arg) do
    arg |> inspect() |> Makeup.highlight_inner_html(lexer: ElixirLexer)
  end

  # Activating or deactivating the Highlighter
  # ------------------------------------------
  defp set_activation_state(activation_state) do
    Application.put_env(:plug, :use_syntax_highlighting_in_debugger, activation_state)
  end

  # Runs a given function with the highlighter in the given state.
  # The highlighter will be restored to its previous state even if the function returns an error.
  defp with_highlighter_activation_set_to(new_activation_state, fun) do
    old_activation_state = is_active?()
    set_activation_state(new_activation_state)
    try do
      result = fun.()
      set_activation_state(old_activation_state)
      result
    rescue
      e ->
        set_activation_state(old_activation_state)
        raise e
    end
  end
end