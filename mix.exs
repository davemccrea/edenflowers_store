defmodule Edenflowers.MixProject do
  use Mix.Project

  def project do
    [
      app: :edenflowers,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :dev,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Edenflowers.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:usage_rules, "~> 0.1"},
      {:ash_authentication_phoenix, "~> 2.0 and < 2.11.0"},
      {:simple_sat, "~> 0.1"},
      {:ash_authentication, "~> 4.0"},
      {:oban, "~> 2.0"},
      {:oban_web, "~> 2.11"},
      {:ash_postgres, "~> 2.0"},
      {:ash_phoenix, "~> 2.0"},
      {:ash_archival, "~> 1.0.4"},
      {:ash_trans, "~> 0.1.0"},
      {:ash, "~> 3.0"},
      {:igniter, "~> 0.4"},
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.4", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons", tag: "v2.2.0", sparse: "optimized", app: false, compile: false, depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:faker, "~> 0.18", only: :test},
      # Waiting for https://github.com/randycoulman/mix_test_interactive/pull/138
      # {:mix_test_interactive, "~> 4.3", only: :dev, runtime: false},
      {:phoenix_test, "~> 0.8", only: :test, runtime: false},
      {:tz, "~> 0.28"},
      {:tailwind_formatter, "~> 0.4.2", only: [:dev, :test], runtime: false},
      {:ex_cldr, "~> 2.40"},
      {:ex_cldr_calendars, "~> 2.0"},
      {:ex_cldr_dates_times, "~> 2.0"},
      {:ex_cldr_plugs, "~> 1.3"},
      {:ex_cldr_languages, "~> 0.3"},
      {:cldr_html, "~> 1.6"},
      {:stripity_stripe, "~> 3.2"},
      {:tidewave, "~> 0.1", only: [:dev]},
      {:mdex, "~> 0.6"},
      {:sqids, "~> 0.2.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ash.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ash.setup --quiet", "test"],
      "assets.setup": ["cmd --cd assets npm install", "tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind edenflowers", "esbuild edenflowers"],
      "assets.deploy": [
        "tailwind edenflowers --minify",
        "esbuild edenflowers --minify",
        "phx.digest"
      ],
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
