defmodule Edenflowers.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :edenflowers

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Looks up the saved card in Stripe for every live subscription that doesn't
  show one yet. Safe to run again: a card that can't be found stays blank.

      bin/edenflowers eval "Edenflowers.Release.backfill_subscription_cards()"
  """
  def backfill_subscription_cards do
    {:ok, _} = Application.ensure_all_started(@app)
    require Ash.Query

    Edenflowers.Orders.Subscription
    |> Ash.Query.filter(is_nil(card_brand) and state != :cancelled)
    |> Ash.read!(actor: Edenflowers.Actors.system_actor())
    |> Enum.map(&Edenflowers.Orders.snapshot_subscription_card(&1, actor: Edenflowers.Actors.system_actor()))
    |> Enum.frequencies_by(fn
      {:ok, %{card_brand: nil}} -> :not_found
      {:ok, _} -> :updated
      {:error, _} -> :failed
    end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
