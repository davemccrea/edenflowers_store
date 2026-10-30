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
    # Worktrees set DATABASE_NAME in .env so parallel test runs don't share a database
    database: "#{System.get_env("DATABASE_NAME", "edenflowers")}_test#{System.get_env("MIX_TEST_PARTITION")}",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
end

config :edenflowers, EdenflowersWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "3Rkkz6a0U24wSHjB0e8Mp3bmn+MiJVwFQHAWQEEGBPQjw41JoepIpLj+MOgJ9t1B",
  server: false

config :edenflowers, Edenflowers.Mailer, adapter: Swoosh.Adapters.Test

config :swoosh, :api_client, false

config :imgproxy, prefix: "http://imgproxy.test"

config :logger, level: :warning

config :error_tracker, enabled: false

config :edenflowers, :error_alert_email, "alerts@example.com"
config :edenflowers, :shop_notice_email, "shop@example.com"

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
config :edenflowers, :papra_base_url, "http://papra.test"
config :edenflowers, :papra_api_key, "test-papra-key"
config :edenflowers, :papra_organization_id, "org_test"
config :edenflowers, :papra_req_options, plug: {Req.Test, Edenflowers.External.PapraAPI}, retry: false
config :edenflowers, :fastmail_api_token, "test-fastmail-token"
config :edenflowers, :fastmail_req_options, plug: {Req.Test, Edenflowers.External.FastmailAPI}, retry: false

config :edenflowers, :brevo_api_key, "test-brevo-key"
config :edenflowers, :brevo_req_options, plug: {Req.Test, Edenflowers.Accounts.Workers.SyncNewsletterList}, retry: false

# Push services are stubbed per test with Req.Test.
config :edenflowers, :web_push_req_options, plug: {Req.Test, Edenflowers.WebPush}

config :edenflowers, :delivery_photo_req_options,
  plug: {Req.Test, Edenflowers.Orders.Order.Changes.SendFulfillmentEmail},
  retry: false
