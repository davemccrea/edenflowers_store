defmodule Edenflowers.Orders.Changes.RemoveCardLineItem do
  @moduledoc "Destroys the order's card line item, if it has one."
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Orders.LineItem

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      with :ok <- destroy_card(order.id), do: {:ok, order}
    end)
  end

  def destroy_card(order_id) do
    LineItem
    |> Ash.Query.filter(order_id == ^order_id and is_card == true)
    |> Ash.bulk_destroy(:remove_item, %{},
      strategy: [:atomic, :stream],
      notify?: true,
      return_errors?: true,
      authorize?: false
    )
    |> case do
      %Ash.BulkResult{status: :success} -> :ok
      %Ash.BulkResult{errors: errors} -> {:error, errors}
    end
  end
end
