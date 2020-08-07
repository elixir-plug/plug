defmodule Plug.MixProject do
  use Mix.Project

  @version "1.10.4"
  @description "A specification and conveniences for composable modules between web applications"
  @xref_exclude [Plug.Cowboy, :telemetry]

  def project do
    [
      app: :plug,
      version: @version,
      elixir: "~> 1.7",
      deps: deps(),
      package: package(),
      description: @description,
      name: "Plug",
      xref: [exclude: @xref_exclude],
      consolidate_protocols: Mix.env() != :test,
      docs: [
        extras: [
          "README.md",
          "guides/https.md"
        ],
        main: "readme",
        groups_for_modules: groups_for_modules(),
        groups_for_extras: groups_for_extras(),
        source_ref: "v#{@version}",
        source_url: "https://github.com/elixir-plug/plug"
      ]
    ]
  end

  # Configuration for the OTP application
  def application do
    [
      extra_applications: [:logger, :eex],
      mod: {Plug.Application, []},
      env: [validate_header_keys_during_test: true]
    ]
  end

  def deps do
    [
      {:mime, "~> 1.0"},
      {:plug_crypto, "~> 1.1.1 or ~> 1.2"},
      {:telemetry, "~> 0.4"},
      {:ex_doc, "~> 0.21", only: :docs}
    ]
  end

  defp package do
    %{
      licenses: ["Apache-2.0"],
      maintainers: ["Gary Rennie", "José Valim"],
      links: %{"GitHub" => "https://github.com/elixir-plug/plug"},
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "src", ".formatter.exs"]
    }
  end

  defp groups_for_modules do
    # Ungrouped Modules
    #
    # Plug
    # Plug.Builder
    # Plug.Conn
    # Plug.Debugger
    # Plug.ErrorHandler
    # Plug.Exception
    # Plug.HTML
    # Plug.Router
    # Plug.Test
    # Plug.Upload

    [
      Plugs: [
        Plug.CSRFProtection,
        Plug.Head,
        Plug.Logger,
        Plug.MethodOverride,
        Plug.Parsers,
        Plug.RequestId,
        Plug.SSL,
        Plug.Session,
        Plug.Static,
        Plug.Telemetry
      ],
      "Plug.Conn": [
        Plug.Conn.Adapter,
        Plug.Conn.Cookies,
        Plug.Conn.Query,
        Plug.Conn.Status,
        Plug.Conn.Unfetched,
        Plug.Conn.Utils
      ],
      "Plug.Parsers": [
        Plug.Parsers.JSON,
        Plug.Parsers.MULTIPART,
        Plug.Parsers.URLENCODED
      ],
      "Plug.Session": [
        Plug.Session.COOKIE,
        Plug.Session.ETS,
        Plug.Session.Store
      ]
    ]
  end

  defp groups_for_extras do
    [
      Guides: ~r/guides\/[^\/]+\.md/
    ]
  end
end
