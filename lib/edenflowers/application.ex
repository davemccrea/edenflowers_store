defmodule Edenflowers.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Oban.Telemetry.attach_default_logger()

    children = [
      EdenflowersWeb.Telemetry,
      Edenflowers.Repo,
      {DNSCluster, query: Application.get_env(:edenflowers, :dns_cluster_query) || :ignore},
      {Oban, Application.fetch_env!(:edenflowers, Oban)},
      {Phoenix.PubSub, name: Edenflowers.PubSub},
      {Edenflowers.RateLimiter, clean_period: :timer.minutes(1)},
      EdenflowersWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :edenflowers]}
    ]

    opts = [strategy: :one_for_one, name: Edenflowers.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    EdenflowersWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
