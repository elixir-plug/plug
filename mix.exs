defmodule Plug.Mixfile do
  use Mix.Project

  @version "1.1.0"

  def project do
    [app: :plug,
     version: @version,
     elixir: "~> 1.0",
     deps: deps,
     package: package,
     description: "A specification and conveniences for composable " <>
                  "modules between web applications",
     name: "Plug",
     docs: [extras: ["README.md"], main: "readme",
            source_ref: "v#{@version}",
            source_url: "https://github.com/elixir-lang/plug"]]
  end

  # Configuration for the OTP application
  def application do
    [applications: [:crypto, :logger],
     mod: {Plug, []}]
  end

  def deps do
    [{:cowboy, "~> 1.0", optional: true},
     {:earmark, "~> 0.1", only: :docs},
     {:ex_doc, "~> 0.11", only: :docs},
     {:inch_ex, ">= 0.0.0", only: :docs},
     {:hackney, "~> 1.2.0", only: :test}]
  end

  defp package do
    %{licenses: ["Apache 2"],
      links: %{"GitHub" => "https://github.com/elixir-lang/plug"}}
  end
end
