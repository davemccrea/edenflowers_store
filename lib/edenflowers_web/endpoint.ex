defmodule EdenflowersWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :edenflowers

  @session_options [
    store: :cookie,
    key: "_edenflowers_key",
    signing_salt: "ZUXNYtPz",
    # Matches the auth token_lifetime in Edenflowers.Accounts.User.
    max_age: 30 * 24 * 60 * 60,
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:uri, session: @session_options]],
    longpoll: [connect_info: [:uri, session: @session_options]]

  # Stripe's Payment Element iframe loads Open Sans cross-origin.
  plug Plug.Static,
    at: "/",
    from: :edenflowers,
    only: ~w(fonts),
    headers: %{"access-control-allow-origin" => "*"}

  plug Plug.Static,
    at: "/",
    from: :edenflowers,
    gzip: not code_reloading?,
    only: EdenflowersWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  if Code.ensure_loaded?(Tidewave) do
    plug Tidewave, toolbar: false
  end

  if code_reloading? do
    plug AshAi.Mcp.Dev,
      # For many tools, you will need to set the `protocol_version_statement` to the older version.
      protocol_version_statement: "2024-11-05",
      otp_app: :edenflowers,
      path: "/ash_ai/mcp"

    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :edenflowers
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Stripe.WebhookPlug,
    at: "/webhook/stripe",
    handler: EdenflowersWeb.Webhooks.StripeHandler,
    secret: {Application, :get_env, [:edenflowers, :stripe_webhook_secret]}

  plug EdenflowersWeb.Plugs.PapraWebhook,
    at: "/webhook/papra",
    handler: EdenflowersWeb.Webhooks.PapraHandler,
    secret: {Application, :get_env, [:edenflowers, :papra_webhook_secret]}

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug EdenflowersWeb.Router
end
