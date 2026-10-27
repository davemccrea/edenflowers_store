defmodule Edenflowers.Orders.Order.Changes.ClearGiftFields do
  @moduledoc """
  An order that isn't a gift has no recipient, recipient phone or card.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.get_attribute(changeset, :gift) do
      changeset
    else
      Ash.Changeset.force_change_attributes(changeset,
        recipient_name: nil,
        recipient_phone_number: nil,
        card_message: nil
      )
    end
  end
end
