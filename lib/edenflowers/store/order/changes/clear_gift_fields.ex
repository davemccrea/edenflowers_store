defmodule Edenflowers.Store.Order.ClearGiftFields do
  @moduledoc """
  Clears gift-related fields when the order is not a gift.

  When the gift flag is set to false, this change clears the
  recipient_name and gift_message fields to ensure no stale
  gift data remains on the order.
  """
  use Ash.Resource.Change

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      gift = Ash.Changeset.get_argument_or_attribute(changeset, :gift)

      if not gift do
        Ash.Changeset.force_change_attributes(changeset, %{
          recipient_name: nil,
          gift_message: nil
        })
      else
        changeset
      end
    end)
  end
end
