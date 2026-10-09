import Config
config :edenflowers, token_signing_secret: "Ru1t3J1eZMoIIz6LEIYtCN9CK7SlGbKg"
config :edenflowers, :uploads_dir, Path.join(System.tmp_dir!(), "edenflowers_test_uploads")

if url = System.get_env("DATABASE_URL") do
  config :edenflowers, Edenflowers.Repo,
    url: url,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
else
  config :edenflowers, Edenflowers.Repo,
    username: "david",
    password: nil,
    hostname: "localhost",
    database: "edenflowers_test#{System.get_env("MIX_TEST_PARTITION")}",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
end

config :edenflowers, EdenflowersWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "3Rkkz6a0U24wSHjB0e8Mp3bmn+MiJVwFQHAWQEEGBPQjw41JoepIpLj+MOgJ9t1B",
  server: false

config :edenflowers, Edenflowers.Mailer, adapter: Swoosh.Adapters.Test

config :swoosh, :api_client, false

config :logger, level: :warning

config :error_tracker, enabled: false

config :edenflowers, :error_alert_email, "alerts@example.com"

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix,
  sort_verified_routes_query_params: true

config :edenflowers, Oban, testing: :manual

config :ash, disable_async?: true

config :phoenix_test, :endpoint, EdenflowersWeb.Endpoint

config :edenflowers, :stripe_api, Edenflowers.External.StripeAPI.Mock
config :edenflowers, :stripe_publishable_key, "pk_test_dummy"

config :edenflowers, :here_api, Edenflowers.External.HereAPI.Mock

config :edenflowers, :papra_api, Edenflowers.External.PapraAPI.Mock
config :edenflowers, :claude_api, Edenflowers.External.ClaudeAPI.Mock
config :edenflowers, :papra_webhook_secret, "test-webhook-secret"
