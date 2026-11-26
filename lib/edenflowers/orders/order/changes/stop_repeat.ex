defmodule Edenflowers.Orders.Order.Changes.StopRepeat do
  @moduledoc "Ends the Repeating order the order belongs to, if any, in the same transaction."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      case Ash.load!(order, :order_repeat, authorize?: false).order_repeat do
        nil -> :ok
        repeat -> Edenflowers.Orders.stop_order_repeat!(repeat, actor: context.actor)
      end

      {:ok, order}
    end)
  end
end
