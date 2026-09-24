defmodule LegionWeb.MixProject do
  use Mix.Project

  @source_url "https://github.com/software-mansion/legion_web"
  @version "0.5.1"

  def project do
    [
      app: :legion_web,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      listeners: [Phoenix.CodeReloader],
      # Hex
      package: package(),
      description: "Dashboard for the Legion AI agent framework",
      # Docs
      name: "LegionWeb",
      docs: [
        main: "readme",
        extras: ["README.md", "LICENSE"],
        api_reference: false,
        source_ref: "v#{@version}",
        source_url: @source_url,
        formatters: ["html"]
      ]
    ]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {LegionWeb.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp package do
    [
      maintainers: ["Software Mansion"],
      licenses: ["MIT"],
      files:
        ~w(lib priv/static/app.css priv/static/app.js .formatter.exs mix.exs README* CHANGELOG* LICENSE*),
      links: %{
        Website: "https://swmansion.com/",
        Changelog: "#{@source_url}/blob/main/CHANGELOG.md",
        GitHub: @source_url
      }
    ]
  end

  defp deps do
    [
      {:legion, "~> 0.5"},
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:makeup, "~> 1.0"},
      {:makeup_syntect, "~> 0.1"},
      {:earmark, "~> 1.4"},

      # Optional
      {:igniter, "~> 0.5", optional: true},
      {:ecto_sql, "~> 3.13", optional: true},
      {:postgrex, "~> 0.22", optional: true},

      # Test and Dev
      {:bandit, "~> 1.5", only: :dev},
      {:esbuild, "~> 0.7", only: :dev, runtime: false},
      {:tailwind, "~> 0.4", only: :dev, runtime: false},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:floki, "~> 0.33", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      "assets.build": ["tailwind legion_web", "esbuild legion_web"],
      dev: "run --no-halt dev.exs",
      release: [
        "assets.build",
        # Exit on assets diff
        "cmd git diff --exit-code -- priv/static",
        "cmd git tag v#{@version}",
        "cmd git push",
        "cmd git push --tags",
        "hex.publish --yes"
      ],
      ci: [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "credo --strict",
        "test --raise"
      ]
    ]
  end
end
