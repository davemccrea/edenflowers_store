defmodule Edenflowers.Orders.Changes.ReactivateSubscription do
  @moduledoc """
  Paying an Occurrence's payment link settles the charge its card refused, so
  a subscription held at `:payment_failed` starts making Occurrences again.
  """
  use Ash.Resource.Change

  import Edenflowers.Actors

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Subscription

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      with {:ok, subscription} <- Orders.get_subscription(order.subscription_id, actor: system_actor()),
           {:ok, _subscription} <- Subscription.reactivate_if_held(subscription) do
        {:ok, order}
      end
    end)
  end
end
