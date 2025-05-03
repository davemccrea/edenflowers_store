defmodule Edenflowers.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
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
      # Start a worker by calling: Edenflowers.Worker.start_link(arg)
      # {Edenflowers.Worker, arg},
      # Start to serve requests, typically the last entry
      EdenflowersWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Edenflowers.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EdenflowersWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
