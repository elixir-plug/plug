# Used by "mix format" and to export configuration.
export_locals_without_parens = [
  plug: 1,
  plug: 2,
  forward: 2,
  forward: 3,
  forward: 4
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: export_locals_without_parens,
  export: [locals_without_parens: export_locals_without_parens]
]
