defmodule Edenflowers.Orders.Changes.PushNewOrder do
  @moduledoc """
  Queues the admin's new-order notification in the placing transaction, so the
  job only runs for an order that was really placed. A failed push never fails
  checkout: delivery happens in the job, after commit.

  Without VAPID keys (staging, most dev machines) nothing is queued.
  """
  use Ash.Resource.Change

  alias Edenflowers.Orders.Workers.PushNewOrder

  @impl true
  def change(changeset, _opts, _context) do
    if Edenflowers.WebPush.configured?() do
      Ash.Changeset.after_action(changeset, fn _changeset, order ->
        order |> PushNewOrder.new_for() |> Oban.insert!()
        {:ok, order}
      end)
    else
      changeset
    end
  end
end
