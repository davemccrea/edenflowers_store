defmodule Edenflowers.Store.LineItem.Changes.MaybeRestartCheckout do
  @moduledoc """
  After a line item is destroyed, restart the order's checkout if the
  cart is now effectively empty and the order is still mid-checkout.

  This enforces the invariant from a single place: no matter who removes
  the last cart item (cart drawer from any page, cart sidebar on /checkout,
  programmatic destroys from other actions), stale checkout form fields
  cannot survive into a future checkout session.

  Callers that destroy line items as part of `restart_checkout` itself
  must set `skip_checkout_reset: true` in the changeset context to break
  the recursion.
  """
  use Ash.Resource.Change

  @checkout_states [:contact_details, :gift_options, :delivery, :payment]

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, &maybe_restart/2)
  end

  defp maybe_restart(changeset, destroyed) do
    if Map.get(changeset.context, :skip_checkout_reset, false) do
      {:ok, destroyed}
    else
      order = Edenflowers.Store.Order.get_for_checkout!(destroyed.order_id, authorize?: false)

      if order.cart_effectively_empty? and order.state in @checkout_states do
        Edenflowers.Store.Order.restart_checkout!(order, authorize?: false)
      end

      {:ok, destroyed}
    end
  end
end
