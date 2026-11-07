defmodule Edenflowers.Orders.Subscription.Changes.QueueSubscriptionCancelledEmail do
  @moduledoc """
  Queues the optional cancellation email when an admin cancels a subscription,
  including any subject and body edits. A customer cancellation always queues
  a confirmation and a shop notice.
  """

  use Ash.Resource.Change

  alias Edenflowers.Orders.Changes.NotifyShop
  alias Edenflowers.Payments.Changes.QueueEmail

  @impl true
  def change(changeset, _opts, context) do
    cond do
      not Map.get(context.actor || %{}, :admin, false) ->
        changeset
        |> QueueEmail.change([trigger: :send_cancellation_confirmed_email], context)
        |> NotifyShop.change([notice: :cancelled], context)

      Ash.Changeset.get_argument(changeset, :email_customer?) ->
        QueueEmail.change(changeset, [trigger: :send_cancelled_email], context)

      true ->
        changeset
    end
  end
end
