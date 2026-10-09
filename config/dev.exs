import Config

config :edenflowers, Edenflowers.Repo,
  username: "david",
  password: nil,
  hostname: "localhost",
  database: "edenflowers_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :edenflowers, EdenflowersWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "aF05r2YhXYvrsf3s+pFP8BN9I60PUt4fF1No0wON3d1NgSBATcyPlFSryjfS2Siy",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:edenflowers, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:edenflowers, ~w(--watch)]}
  ]

config :edenflowers, EdenflowersWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
      ~r"priv/gettext/.*\.po$"E
    ]
  ]

config :edenflowers, dev_routes: true, token_signing_secret: "gfVwyABSNkPTnaZdjgjlMpEoNPEvxcgQ"

# Stripe's public test key, so dev boots without STRIPE_PUBLISHABLE_KEY.
config :edenflowers,
       :stripe_publishable_key,
       System.get_env("STRIPE_PUBLISHABLE_KEY") || "pk_test_3gvP7KfmcinLf52LVqP6JstL00Rr9tIeXM"

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Include debug annotations and locations in rendered markup.
  # Changing this configuration will require mix clean and a full recompile.
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true

config :swoosh, :api_client, false
