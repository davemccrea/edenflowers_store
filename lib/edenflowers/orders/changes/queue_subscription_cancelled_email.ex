defmodule Edenflowers.Orders.Changes.QueueSubscriptionCancelledEmail do
  @moduledoc """
  Queues the emails a cancelled subscription sends. When Jennie cancels it,
  Subscription cancelled with her message, if she ticks it. When the customer
  cancels it in their account, the matter-of-fact confirmation, and a shop
  notice so Jennie hears about it.
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
