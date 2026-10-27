defmodule Edenflowers.Orders.Order.Changes.SetContactPhoneNumber do
  @moduledoc """
  Writes checkout's one phone field, the `contact_phone_number` argument, to
  the number it is: the Recipient's on a gift delivery, otherwise the
  Customer's own. Any other order has no Recipient to call, so a number left
  from an earlier gift delivery choice is cleared.

  Runs after `SnapshotFulfillmentMethod`, which decides whether it's a delivery.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    phone_number = Ash.Changeset.get_argument(changeset, :contact_phone_number)

    if Ash.Changeset.get_attribute(changeset, :gift) and
         Ash.Changeset.get_attribute(changeset, :fulfillment_method) == :delivery do
      Ash.Changeset.force_change_attribute(changeset, :recipient_phone_number, phone_number)
    else
      Ash.Changeset.force_change_attributes(changeset,
        customer_phone_number: phone_number,
        recipient_phone_number: nil
      )
    end
  end
end
