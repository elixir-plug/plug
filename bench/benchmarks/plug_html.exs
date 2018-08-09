inputs = %{
  "small clean" => String.duplicate("abcdefghijklmno", 100),
  "small html"  => String.duplicate("abcde<foo>fghij", 100),
  "large clean" => String.duplicate("abcdefghijklmno", 100_000),
  "large html"  => String.duplicate("abcde<foo>fghij", 100_000)
}

jobs = %{
  "html_escape" => fn data -> Plug.HTML.html_escape(data) end,
  "html_escape_to_iodata" => fn data -> Plug.HTML.html_escape_to_iodata(data) end,
}

path = System.get_env("BENCHMARKS_OUTPUT_PATH") || raise "I DON'T KNOW WHERE TO WRITE!!!"
file = Path.join(path, "html_generator.json")

Benchee.run(
  jobs,
  inputs: inputs,
  time: 15,
  formatters: [Benchee.Formatters.JSON],
  formatter_options: [json: [file: file]]
)

