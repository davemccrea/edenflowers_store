import Config
config :edenflowers, token_signing_secret: "Ru1t3J1eZMoIIz6LEIYtCN9CK7SlGbKg"
config :bcrypt_elixir, log_rounds: 1

# Set dummy values for required environment variables in test
System.put_env("HERE_API_KEY", "test_here_api_key")
System.put_env("STRIPE_API_KEY", "sk_test_dummy_key")
System.put_env("STRIPE_WEBHOOK_SECRET", "whsec_test_dummy_secret")

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :edenflowers, Edenflowers.Repo,
  username: "david",
  password: nil,
  hostname: "localhost",
  database: "edenflowers_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :edenflowers, EdenflowersWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "3Rkkz6a0U24wSHjB0e8Mp3bmn+MiJVwFQHAWQEEGBPQjw41JoepIpLj+MOgJ9t1B",
  server: false

# In test we don't send emails
config :edenflowers, Edenflowers.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :edenflowers, Oban, testing: :manual

config :ash, disable_async?: true

config :phoenix_test, :endpoint, EdenflowersWeb.Endpoint
