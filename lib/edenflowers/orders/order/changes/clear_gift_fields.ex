defmodule Edenflowers.Orders.Order.Changes.ClearGiftFields do
  @moduledoc """
  When the gift flag is set to false, clears `recipient_name` and `card_message`
  and destroys the card line item, if any.
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
          Edenflowers.Orders.LineItem
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

  # Atomic counterpart for the attribute-set portion only. The after_action
  # card-cleanup is intentionally not atomic and continues to run via change/3
  # whenever the host action is non-atomic.
  @impl true
  def atomic(changeset, _opts, _context) do
    case Ash.Changeset.get_argument_or_attribute(changeset, :gift) do
      false -> {:atomic, %{recipient_name: nil, card_message: nil}}
      _ -> {:atomic, %{}}
    end
  end
end
