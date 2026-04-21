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
    Ash.Changeset.before_action(changeset, fn changeset ->
      gift = Ash.Changeset.get_argument_or_attribute(changeset, :gift)

      if not gift do
        changeset = Ash.Changeset.force_change_attributes(changeset, %{recipient_name: nil, card_message: nil})

        Ash.Changeset.after_action(changeset, fn _changeset, result ->
          Edenflowers.Store.LineItem
          |> Ash.Query.filter(order_id == ^result.id and is_card == true)
          |> Ash.bulk_destroy(:remove_item, %{}, authorize?: false, return_errors?: true, strategy: [:stream])
          |> case do
            %Ash.BulkResult{status: :success} -> {:ok, result}
            %Ash.BulkResult{errors: errors} -> {:error, errors}
          end
        end)
      else
        changeset
      end
    end)
  end
end
