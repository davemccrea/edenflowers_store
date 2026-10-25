defmodule Edenflowers.Orders.Order.Changes.SetGiftFromRecipient do
  @moduledoc """
  A Subscription has no gift flag of its own: an Occurrence is a gift when
  the Subscription delivers to a recipient.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    recipient_name = Ash.Changeset.get_attribute(changeset, :recipient_name)
    Ash.Changeset.force_change_attribute(changeset, :gift, is_binary(recipient_name) and recipient_name != "")
  end
end
