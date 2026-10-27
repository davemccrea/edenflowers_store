import Config

# Load .env so mix works without `source .env`, which Claude Code's worktree isolation refuses.
# Without it a worktree silently falls back to main's database. Variables already set win.
if config_env() != :prod and File.exists?(".env") do
  for "export " <> pair <- File.read!(".env") |> String.split("\n", trim: true),
      [key, value] = String.split(pair, "=", parts: 2),
      System.get_env(key) == nil do
    System.put_env(key, value)
  end
end

config :ash_oban, pro?: false
config :cinder, default_theme: "daisy_ui", gettext_backend: EdenflowersWeb.Gettext, show_filters: :toggle_open

config :edenflowers, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10],
  repo: Edenflowers.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    # A job killed mid-run stays `executing`, and AshOban's uniqueness then
    # blocks that record's trigger for good. Rescued after an hour.
    Oban.Plugins.Lifeline,
    # AshOban adds each trigger's `scheduler_cron` here, so they run on shop time too.
    {Oban.Plugins.Cron,
     timezone: "Europe/Helsinki",
     crontab: [
       {"0 3 * * *", Edenflowers.Accounts.Workers.SyncNewsletterList},
       {"30 3 * * *", Edenflowers.ErrorReports.PruneReports}
     ]}
  ]

config :localize,
  supported_locales: ["en-GB", "sv-FI", "fi"],
  default_locale: "en-GB",
  gettext: EdenflowersWeb.Gettext,
  allow_runtime_locale_download: true

config :ash,
  include_embedded_source_by_default?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  default_string_length_count: :codepoints,
  custom_expressions: [Edenflowers.Expressions.HelsinkiToday]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :authentication,
        :tokens,
        :postgres,
        :translations,
        :resource,
        :archive,
        :state_machine,
        :oban,
        :paper_trail,
        :rate_limit,
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
  ash_domains: [
    Edenflowers.Accounts,
    Edenflowers.Catalog,
    Edenflowers.Orders,
    Edenflowers.Fulfillment,
    Edenflowers.Pricing,
    Edenflowers.Courses,
    Edenflowers.Payments,
    Edenflowers.Expenses
  ]

# Admin photo uploads. Dev keeps them out of images/, the photos synced to the
# servers; `just start-imgproxy` serves them. Production sets UPLOADS_DIR to a folder
# inside imgproxy's images dir.
config :edenflowers, :uploads_dir, "tmp/uploads"

config :edenflowers, :ash_rate_limiter, hammer: Edenflowers.RateLimiter

config :edenflowers, EdenflowersWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: EdenflowersWeb.ErrorHTML, json: EdenflowersWeb.ErrorJSON],
    root_layout: [html: {EdenflowersWeb.Layouts, :root}],
    layout: false
  ],
  pubsub_server: Edenflowers.PubSub,
  live_view: [signing_salt: "fZLlI7wP"]

config :edenflowers, Edenflowers.Mailer, adapter: Swoosh.Adapters.Local

# Default sender identity. Overridden in runtime.exs from MAILER_FROM_NAME / MAILER_FROM_EMAIL.
config :edenflowers, :mailer_from_address, {"Jennie", "info@edenflowers.fi"}

config :esbuild,
  version: "0.25.4",
  edenflowers: [
    args:
      ~w(js/app.js --bundle --splitting --format=esm --chunk-names=chunks/[name]-[hash] --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.1.12",
  edenflowers: [
    args: ~w(

      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

config :error_tracker,
  repo: Edenflowers.Repo,
  otp_app: :edenflowers,
  enabled: true

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"

config :elixir, :time_zone_database, Tz.TimeZoneDatabase
