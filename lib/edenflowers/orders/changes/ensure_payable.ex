defmodule Edenflowers.Orders.Changes.EnsurePayable do
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Orders.Order

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      order_id = changeset.data.id

      order =
        Order
        |> Ash.Query.filter(id == ^order_id)
        |> Ash.Query.lock(:for_update)
        |> Ash.Query.load([:balance, :payment_status])
        |> Ash.read_one!(authorize?: false)

      if order.fulfillment_status == :cancelled or order.payment_status == :refunded or
           not Decimal.positive?(order.balance) do
        Ash.Changeset.add_error(changeset, field: :payment_intent_id, message: "order is not payable")
      else
        changeset
      end
    end)
  end
end
