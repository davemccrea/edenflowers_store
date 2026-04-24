defmodule Edenflowers.MixProject do
  use Mix.Project

  def project do
    [
      app: :edenflowers,
      version: "0.2.8",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :dev,
      aliases: aliases(),
      deps: deps(),
      releases: [edenflowers: [strip_beams: true]],
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      usage_rules: [
        skills: [
          location: ".claude/skills",
          package_skills: [:gettext_sigils],
          build: [
            "ash-framework": [
              description: "Expert on the Ash Framework ecosystem.",
              usage_rules: [:ash, ~r/^ash_/]
            ],
            "phoenix-framework": [
              description: "Expert on the Phoenix Framework.",
              usage_rules: [:phoenix, ~r/^phoenix_/]
            ],
            "elixir-otp": [
              description: "Expert on Elixir and OTP.",
              usage_rules: [:elixir, :otp]
            ],
            igniter: [
              description: "Expert on Igniter.",
              usage_rules: [:igniter]
            ]
          ]
        ]
      ]
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
      {:usage_rules, "~> 1.1", only: [:dev]},
      {:ash_authentication_phoenix, "~> 2.16.0"},
      {:simple_sat, "~> 0.1"},
      {:ash_authentication, "~> 4.0"},
      {:oban, "~> 2.0"},
      {:oban_web, "~> 2.11"},
      {:ash_postgres, "~> 2.0"},
      {:ash_phoenix, "~> 2.0"},
      {:ash_archival, "~> 2.0.3"},
      {:ash_translation, "~> 0.2.0"},
      {:ash_state_machine, "~> 0.2.12"},
      {:ash, "~> 3.0"},
      {:igniter, "~> 0.4"},
      {:phoenix, "~> 1.8.5"},
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
      {:gettext, "~> 1.0"},
      {:gettext_sigils, "~> 0.5"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:faker, "~> 0.18", only: :test},
      {:mox, "~> 1.0", only: :test},
      # Waiting for https://github.com/randycoulman/mix_test_interactive/pull/138
      # {:mix_test_interactive, "~> 4.3", only: :dev, runtime: false},
      {:phoenix_test, "~> 0.8", only: :test, runtime: false},
      {:tz, "~> 0.28"},
      {:tailwind_formatter, "~> 0.4.2", only: [:dev, :test], runtime: false},
      {:localize, "~> 0.1"},
      {:localize_web, "~> 0.1"},
      {:stripity_stripe, "~> 3.2"},
      {:tidewave, "~> 0.1", only: [:dev]},
      {:mdex, "~> 0.6"},
      {:imgproxy, "~> 3.1"}
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
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind edenflowers", "esbuild edenflowers"],
      "assets.deploy": [
        "tailwind edenflowers --minify",
        "esbuild edenflowers --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format --check-formatted", "test"]
    ]
  end
end
