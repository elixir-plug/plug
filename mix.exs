defmodule Plug.Mixfile do
  use Mix.Project

  def project do
    [ app: :plug,
      version: "0.1.0",
      elixir: "~> 0.11.2",
      deps: deps(Mix.env),
      docs: [ readme: true, main: "README" ] ]
  end

  # Configuration for the OTP application
  def application do
    [ applications: [:crypto],
      mod: { Plug, [] } ]
  end

  def deps(:prod) do
    [ { :cowboy, "~> 0.9", github: "extend/cowboy", optional: true } ]
  end

  def deps(:docs) do
    deps(:prod) ++
      [ { :ex_doc, github: "elixir-lang/ex_doc" } ]
  end

  def deps(_) do
    deps(:prod) ++
      [ { :hackney, github: "benoitc/hackney" } ]
  end
end
