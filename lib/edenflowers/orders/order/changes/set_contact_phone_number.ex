defmodule Edenflowers.Orders.Order.Changes.SetContactPhoneNumber do
  @moduledoc """
  Stores `contact_phone_number` as `recipient_phone_number` for gift deliveries.
  Otherwise stores it as `customer_phone_number` and clears `recipient_phone_number`.

  Runs after `SnapshotFulfillmentMethod`.
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
