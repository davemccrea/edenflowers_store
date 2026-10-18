defmodule Edenflowers.Orders.Changes.ClearGiftFields do
  @moduledoc """
  An order that isn't a gift has no recipient or card. On a Custom Order the
  recipient's phone goes too, as the customer's own number is kept apart; an
  Online Order keeps it, since checkout stores the buyer's number there.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.get_attribute(changeset, :gift) do
      changeset
    else
      changeset
      |> Ash.Changeset.force_change_attributes(recipient_name: nil, card_message: nil)
      |> clear_recipient_phone()
    end
  end

  defp clear_recipient_phone(changeset) do
    if Ash.Changeset.get_attribute(changeset, :origin) == :custom,
      do: Ash.Changeset.force_change_attribute(changeset, :recipient_phone_number, nil),
      else: changeset
  end
end
