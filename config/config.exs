# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :edenflowers, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10],
  repo: Edenflowers.Repo,
  plugins: [
    # {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    # TODO: maybe enabled priner and reindexer at some point
    # {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    # Oban.Plugins.Reindexer,
    # {Oban.Plugins.Cron,
    #  crontab: [
    #    # Run every Sunday at 18:00
    #    {"0 18 * * SUN", Edenflowers.Workers.WeeklyRecap}
    #  ]}
  ]

config :ex_cldr,
  default_locale: "en",
  default_backend: Edenflowers.Cldr

config :ash,
  include_embedded_source_by_default?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :authentication,
        :tokens,
        :postgres,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [section_order: [:resources, :policies, :authorization, :domain, :execution]]
  ]

config :edenflowers,
  ecto_repos: [Edenflowers.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [Edenflowers.Accounts, Edenflowers.Store, Edenflowers.Services]

# Configures the endpoint
config :edenflowers, EdenflowersWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: EdenflowersWeb.ErrorHTML, json: EdenflowersWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Edenflowers.PubSub,
  live_view: [signing_salt: "fZLlI7wP"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :edenflowers, Edenflowers.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  edenflowers: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.0",
  edenflowers: [
    args: ~w(

      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

config :elixir, :time_zone_database, Tz.TimeZoneDatabase
