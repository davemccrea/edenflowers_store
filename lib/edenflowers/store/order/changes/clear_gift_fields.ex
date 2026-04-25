defmodule Edenflowers.Store.Order.Changes.ClearGiftFields do
  @moduledoc """
  Clears gift-related fields and removes the card line item when the order is not a gift.

  When the gift flag is set to false, this change clears the recipient_name and
  card_message fields and destroys the card line item attached to the order, if any.
  """
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      gift = Ash.Changeset.get_argument_or_attribute(changeset, :gift)

      if not gift do
        changeset = Ash.Changeset.force_change_attributes(changeset, %{recipient_name: nil, card_message: nil})

        Ash.Changeset.after_action(changeset, fn _changeset, result ->
          Edenflowers.Store.LineItem
          |> Ash.Query.filter(order_id == ^result.id and is_card == true)
          |> Ash.read_one(authorize?: false)
          |> case do
            {:ok, nil} ->
              {:ok, result}

            {:ok, line_item} ->
              case Ash.destroy(line_item, action: :remove_item, authorize?: false) do
                :ok -> {:ok, result}
                {:error, error} -> {:error, error}
              end

            {:error, error} ->
              {:error, error}
          end
        end)
      else
        changeset
      end
    end)
  end
end
