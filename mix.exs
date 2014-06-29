defmodule Plug.Mixfile do
  use Mix.Project

  def project do
    [app: :plug,
     version: "0.5.1",
     elixir: "~> 0.14.0",
     deps: deps,
     package: package,
     description: "A specification and conveniences for composable " <>
                  "modules in between web applications",
     docs: [readme: true, main: "README"]]
  end

  # Configuration for the OTP application
  def application do
    [applications: [:crypto],
     mod: {Plug, []}]
  end

  def deps do
    [{:cowboy, "~> 0.10.0", github: "extend/cowboy", optional: true},
     {:ex_doc, github: "elixir-lang/ex_doc", only: [:docs]},
     {:hackney, github: "benoitc/hackney", only: [:test]}]
  end

  defp package do
    %{licenses: ["Apache 2"],
      links: %{"Github" => "https://github.com/elixir-lang/plug"}}
  end
end
