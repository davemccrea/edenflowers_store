defmodule Edenflowers.Orders.Changes.QueueSubscriptionCancelledEmail do
  @moduledoc """
  Queues the customer's email when a subscription is cancelled: Subscription
  cancelled, with Jennie's message, when she cancels it and ticks the email.
  """

  use Ash.Resource.Change

  alias Edenflowers.Payments.Changes.QueueEmail

  @impl true
  def change(changeset, _opts, context) do
    if Map.get(context.actor || %{}, :admin) && Ash.Changeset.get_argument(changeset, :email_customer?),
      do: QueueEmail.change(changeset, [trigger: :send_cancelled_email], context),
      else: changeset
  end
end
