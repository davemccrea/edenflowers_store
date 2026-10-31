defmodule Edenflowers.MixProject do
  use Mix.Project

  def project do
    [
      app: :edenflowers,
      version: "1.23.0",
      elixir: "~> 1.18",
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
              usage_rules: [:ash, ~r/^ash_/, :spark, :reactor, :cinder]
            ],
            "phoenix-framework": [
              description: "Expert on the Phoenix Framework.",
              usage_rules: [:phoenix, ~r/^phoenix_/]
            ],
            "elixir-otp": [
              description: "Expert on Elixir and OTP.",
              usage_rules: [:usage_rules]
            ],
            igniter: [
              description: "Expert on Igniter.",
              usage_rules: [:igniter]
            ],
            "req-llm": [
              description: "Expert on ReqLLM for making LLM API requests.",
              usage_rules: [:req_llm, :llm_db]
            ],
            localize: [
              description: "Expert on Localize for internationalisation.",
              usage_rules: [:localize]
            ]
          ]
        ]
      ]
    ]
  end

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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ash_oban, "~> 0.4"},
      # Ash
      {:ash, "~> 3.0"},
      {:ash_admin, "~> 1.0"},
      {:ash_archival, "~> 2.0.3"},
      {:ash_paper_trail, "~> 0.8.1"},
      {:ash_authentication, "~> 5.0.0-rc.8"},
      {:ash_authentication_phoenix, "~> 3.0.0-rc.4"},
      {:ash_phoenix, "~> 2.0"},
      {:ash_postgres, "~> 2.0"},
      {:ash_rate_limiter, "~> 2.0"},
      {:ash_state_machine, "~> 0.2.12"},
      {:ash_translation, "~> 0.2.0"},
      {:cinder, "~> 0.14"},
      {:simple_sat, "~> 0.1"},
      # Phoenix & web
      {:bandit, "~> 1.5"},
      {:phoenix, "~> 1.8.5"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_dashboard, "~> 0.9"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2"},
      {:live_select, "~> 1.7.5"},
      # Database
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      # Background jobs
      {:oban, "~> 2.0"},
      {:oban_web, "~> 2.11"},
      # Error tracking
      {:error_tracker, "~> 0.9.0"},
      # Assets
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons", tag: "v2.2.0", sparse: "optimized", app: false, compile: false, depth: 1},
      {:imgproxy, "~> 3.1"},
      {:tailwind, "~> 0.4", runtime: Mix.env() == :dev},
      # Internationalisation
      {:gettext, "~> 1.0"},
      {:gettext_sigils, "~> 0.5"},
      {:localize, "~> 1.2"},
      {:localize_web, "~> 1.1.0"},
      # Telemetry
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      # Integrations
      {:req_llm, "~> 1.18"},
      {:stripity_stripe, "~> 3.2"},
      {:swoosh, "~> 1.16"},
      # Utilities
      {:hammer, "~> 7.0"},
      {:ex_phone_number, "~> 0.4"},
      {:jason, "~> 1.2"},
      {:web_push_ex, "~> 0.2"},
      {:elixlsx, "~> 0.6"},
      {:req, "~> 0.5"},
      {:tz, "~> 0.28"},
      {:mdex, "~> 0.14"},
      # Dev & build tooling
      {:igniter, "~> 0.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:tailwind_formatter, "~> 0.4.2", only: [:dev, :test], runtime: false},
      {:tidewave, "~> 0.9", only: [:dev]},
      {:usage_rules, "~> 1.1", only: [:dev]},
      # Test
      {:lazy_html, ">= 0.1.0", only: :test},
      {:mox, "~> 1.0", only: :test},
      {:phoenix_test, "~> 0.8", only: :test, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "localize.download_locales", "ash.setup", "assets.setup", "assets.build"],
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
      precommit: [
        &check_critical_advisories/1,
        "compile --warnings-as-errors",
        "gettext.check",
        "ash.codegen --check",
        "deps.unlock --check-unused",
        "format --check-formatted",
        "credo --strict",
        "cmd node --test --test-reporter=dot test/js/*_test.mjs",
        "test"
      ]
    ]
  end

  # hex.audit fails on any advisory; only critical ones should block a push or deploy.
  defp check_critical_advisories(_args) do
    {output, status} = System.cmd("mix", ["hex.audit"], stderr_to_stdout: true)
    [unignored | _] = String.split(output, "Ignored advisories:")

    if status != 0 and unignored =~ "(CRITICAL)" do
      Mix.shell().info(output)
      Mix.raise("Dependencies have critical security advisories")
    end
  end
end
