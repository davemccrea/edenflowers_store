defmodule Edenflowers.Orders.Changes.QueueFulfillmentEmail do
  use Ash.Resource.Change

  alias Edenflowers.Orders.FulfillmentEmail
  alias Edenflowers.Orders.Order

  @impl true
  def change(changeset, opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      if Order.fulfillment_email_pending?(order) do
        if opts[:retry?] do
          FulfillmentEmail.retry(order, context.actor)
        else
          AshOban.run_trigger(order, :send_delivered_email, actor: context.actor)
        end
      end

      {:ok, order}
    end)
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
