import Config

if config_env() in [:prod, :dev] do
  if System.get_env("PHX_SERVER") do
    config :edenflowers, EdenflowersWeb.Endpoint, server: true
  end

  config :edenflowers, EdenflowersWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

  if config_env() == :dev do
    config :edenflowers, Edenflowers.Repo, database: System.get_env("DATABASE_NAME", "edenflowers_dev")
  end

  config :edenflowers,
         :here_api_key,
         System.get_env("HERE_API_KEY") || raise("environment variable HERE_API_KEY is missing.")

  # Used by the admin order page's delivery map and `mix eden.fetch_map`. Not
  # raised on absence so contributors can start the app without one; the order
  # page just hides the map.
  config :edenflowers, :mapbox_token, System.get_env("MAPBOX_TOKEN")

  config :imgproxy,
    prefix: System.get_env("IMGPROXY_PREFIX") || raise("environment variable IMGPROXY_PREFIX is missing."),
    key: System.get_env("IMGPROXY_KEY") || raise("environment variable IMGPROXY_KEY is missing."),
    salt: System.get_env("IMGPROXY_SALT") || raise("environment variable IMGPROXY_SALT is missing.")

  config :stripity_stripe,
    api_key: System.get_env("STRIPE_SECRET_KEY") || raise("environment variable STRIPE_SECRET_KEY is missing.")

  config :edenflowers,
         :stripe_webhook_secret,
         System.get_env("STRIPE_WEBHOOK_SECRET") || raise("environment variable STRIPE_WEBHOOK_SECRET is missing.")

  config :edenflowers,
         :stripe_publishable_key,
         System.get_env("STRIPE_PUBLISHABLE_KEY") ||
           raise("environment variable STRIPE_PUBLISHABLE_KEY is missing.")

  config :edenflowers, :maintenance_mode, System.get_env("MAINTENANCE_MODE") in ~w(true 1)

  config :edenflowers,
         :papra_base_url,
         System.get_env("PAPRA_BASE_URL") || raise("environment variable PAPRA_BASE_URL is missing.")

  config :edenflowers,
         :papra_api_key,
         System.get_env("PAPRA_API_KEY") || raise("environment variable PAPRA_API_KEY is missing.")

  config :edenflowers,
         :papra_webhook_secret,
         System.get_env("PAPRA_WEBHOOK_SECRET") || raise("environment variable PAPRA_WEBHOOK_SECRET is missing.")

  config :edenflowers,
         :papra_organization_id,
         System.get_env("PAPRA_ORGANIZATION_ID") || raise("environment variable PAPRA_ORGANIZATION_ID is missing.")

  config :edenflowers,
         :anthropic_api_key,
         System.get_env("ANTHROPIC_API_KEY") || raise("environment variable ANTHROPIC_API_KEY is missing.")

  config :edenflowers,
         :mailer_from_address,
         {System.get_env("MAILER_FROM_NAME", "Jennie"), System.get_env("MAILER_FROM_EMAIL", "info@edenflowers.fi")}
end

if config_env() == :prod do
  config :edenflowers,
         :uploads_dir,
         System.get_env("UPLOADS_DIR") || raise("environment variable UPLOADS_DIR is missing.")

  # Set on the production server only, so staging doesn't send alerts.
  if error_alert_email = System.get_env("ERROR_ALERT_EMAIL") do
    config :edenflowers, :error_alert_email, error_alert_email
  end

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :edenflowers, Edenflowers.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :edenflowers, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :edenflowers, EdenflowersWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  config :edenflowers,
    token_signing_secret:
      System.get_env("TOKEN_SIGNING_SECRET") || raise("Missing environment variable `TOKEN_SIGNING_SECRET`!")

  config :edenflowers, Edenflowers.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: "smtp.fastmail.com",
    port: 587,
    tls: :always,
    auth: :always,
    no_mx_lookups: true,
    username: System.get_env("SMTP_USERNAME") || raise("environment variable SMTP_USERNAME is missing."),
    password: System.get_env("SMTP_PASSWORD") || raise("environment variable SMTP_PASSWORD is missing."),
    tls_options: [
      verify: :verify_peer,
      # gen_smtp defaults to depth 0, which rejects Fastmail's intermediate CA.
      depth: 3,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: ~c"smtp.fastmail.com",
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]
end
