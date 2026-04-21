defmodule Edenflowers.Store.Order.ClearGiftFields do
  @moduledoc """
  Clears gift-related fields and removes card line items when the order is not a gift.

  When the gift flag is set to false, this change clears the recipient_name and
  card_message fields and destroys any card line items attached to the order.
  """
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      gift = Ash.Changeset.get_argument_or_attribute(changeset, :gift)

      if not gift do
        Ash.Changeset.force_change_attributes(changeset, %{recipient_name: nil, card_message: nil})
      else
        changeset
      end
    end)
    |> Ash.Changeset.after_action(fn _changeset, result ->
      if not result.gift do
        Edenflowers.Store.LineItem
        |> Ash.Query.filter(order_id == ^result.id and is_card == true)
        |> Ash.read!(authorize?: false)
        |> Enum.each(&Ash.destroy!(&1, action: :remove_item, authorize?: false))
      end

      {:ok, result}
    end)
  end
end
