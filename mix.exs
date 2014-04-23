defmodule Plug.Mixfile do
  use Mix.Project

  def project do
    [ app: :plug,
      version: "0.4.0",
      elixir: "~> 0.13.0",
      deps: deps,
      docs: [readme: true, main: "README"] ]
  end

  # Configuration for the OTP application
  def application do
    [ applications: [:crypto],
      mod: {Plug, []} ]
  end

  def deps do
    [{:cowboy, "~> 0.9", github: "extend/cowboy", optional: true},
     {:ex_doc, github: "elixir-lang/ex_doc", only: [:docs]},
     {:hackney, github: "benoitc/hackney", only: [:test]}]
  end
end
