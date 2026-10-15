defmodule Edenflowers.Orders.Changes.PushNewOrder do
  @moduledoc """
  Queues the admin's new-order notification in the placing transaction, so the
  job only runs for an order that was really placed.

  A notification is a nicety: if queueing it fails, checkout still succeeds.
  Without VAPID keys (staging, most dev machines) nothing is queued.
  """
  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Orders.Workers.PushNewOrder

  @impl true
  def change(changeset, _opts, _context) do
    if Edenflowers.WebPush.configured?() do
      Ash.Changeset.after_action(changeset, fn _changeset, order ->
        with {:error, reason} <- order |> PushNewOrder.new_for() |> Oban.insert() do
          Logger.warning("Could not queue the new-order push for #{order.id}: #{inspect(reason)}")
        end

        {:ok, order}
      end)
    else
      changeset
    end
  end
end
