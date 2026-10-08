defmodule Edenflowers.Orders.Changes.ReplaceCart do
  @moduledoc """
  Empties the cart, all but a card, when the line being added replaces it
  (`Order.replaced_by_adding?`).
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Orders.LineItem
  alias Edenflowers.Orders.Order

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, &replace(&1, context))
  end

  defp replace(changeset, context) do
    order_id = Ash.Changeset.get_attribute(changeset, :order_id)

    args = %{
      product_id: Ash.Changeset.get_attribute(changeset, :product_id),
      subscription?: not is_nil(Ash.Changeset.get_attribute(changeset, :interval_weeks))
    }

    with false <- Ash.Changeset.get_attribute(changeset, :is_card) || false,
         {:ok, %Order{replaced_by_adding?: true}} <-
           Ash.get(Order, order_id, Ash.Context.to_opts(context, load: [replaced_by_adding?: args])),
         :ok <- destroy_non_card_lines(order_id, context) do
      changeset
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
      _not_replacing -> changeset
    end
  end

  defp destroy_non_card_lines(order_id, context) do
    LineItem
    |> Ash.Query.filter(order_id == ^order_id and is_card == false)
    |> Ash.bulk_destroy(
      :remove_item,
      %{},
      Ash.Context.to_opts(context,
        strategy: [:atomic, :stream],
        notify?: true,
        return_errors?: true
      )
    )
    |> case do
      %Ash.BulkResult{status: :success} -> :ok
      %Ash.BulkResult{errors: errors} -> {:error, errors}
    end
  end
end
