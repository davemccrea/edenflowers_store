defmodule Edenflowers.Store.LineItem.Checks.OrderIsGiftInCheckout do
  @moduledoc """
  Policy check that authorizes `:add_card` only when the target order is a gift
  in the checkout state.

  Expression-based filter policies cannot reference relationships on create
  actions (no row exists yet to filter), so this check reads the order
  directly from the `order_id` attribute on the changeset. The lookup goes
  through `Order`'s own read policy — which authorizes `state == :checkout`
  reads — so no `authorize?: false` bypass is needed.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "order is a gift in checkout state"

  @impl true
  def match?(actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    case Ash.Changeset.get_attribute(changeset, :order_id) do
      nil ->
        false

      order_id ->
        case Edenflowers.Store.Order.get_by_id(order_id, actor: actor) do
          {:ok, %{gift: true, state: :checkout}} -> true
          _ -> false
        end
    end
  end

  def match?(_actor, _context, _opts), do: false
end
