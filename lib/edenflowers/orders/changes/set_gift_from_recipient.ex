defmodule Edenflowers.Orders.Changes.SetGiftFromRecipient do
  @moduledoc """
  Checkout asks "for me or for somebody else"; on a custom order Jennie only
  fills in a recipient when it is somebody else.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    recipient_name = Ash.Changeset.get_attribute(changeset, :recipient_name)
    Ash.Changeset.force_change_attribute(changeset, :gift, is_binary(recipient_name) and recipient_name != "")
  end
end
