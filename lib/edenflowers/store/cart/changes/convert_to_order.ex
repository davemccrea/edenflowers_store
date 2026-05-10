defmodule Edenflowers.Store.Cart.Changes.ConvertToOrder do
  @moduledoc """
  Snapshots the cart into a fresh `Order` (and `OrderLineItem` rows), then
  links the cart to the order via `order_id`.

  Invariants this code preserves (each one is an explicit "easy to get
  wrong" call-out from the architectural decision in
  docs/adr/0001-split-order-into-cart-and-order.md):

    * **Discount amount, not promotion.** We snapshot the computed
      `discount_amount` aggregate onto the order. A later edit to the
      promotion's percentage must not retroactively change the discount on
      a placed order.
    * **Geocoded distance and fulfillment_amount, not fulfillment_option_id.**
      We copy the resolved geocoded fields and the calculated
      `fulfillment_amount`. A later edit to the option's pricing must not
      retroactively change the delivery cost on a placed order.
    * **Customer/recipient names and emails.** Frozen at place-time. A later
      account edit must not back-edit older orders.
    * **Tax amount, total.** The numbers on the receipt must match what was
      charged.

  Runs in `before_action`: the order has to exist before the cart row's
  state transition completes, so the cart's `order_id` FK can be set in the
  same transaction.
  """
  use Ash.Resource.Change
  require Ash.Query
  import Edenflowers.Actors

  alias Edenflowers.Store.{CartLineItem, Order, OrderLineItem}

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      cart =
        Ash.load!(
          changeset.data,
          [
            :total,
            :tax_amount,
            :fulfillment_tax_amount,
            :line_total,
            :line_tax_amount,
            :discount_amount,
            :line_items
          ],
          authorize?: false,
          lazy?: true
        )

      attrs = snapshot_attrs(cart)

      with {:ok, order} <-
             Order
             |> Ash.Changeset.for_create(:place_from_cart, attrs)
             |> Ash.create(actor: system_actor(), authorize?: false),
           {:ok, _line_items} <- snapshot_line_items(cart, order) do
        Ash.Changeset.force_change_attribute(changeset, :order_id, order.id)
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  defp snapshot_attrs(cart) do
    %{
      order_reference: cart.order_reference,
      user_id: cart.user_id,
      payment_intent_id: cart.payment_intent_id,
      ordered_at: DateTime.utc_now(),
      payment_status: :paid,
      fulfillment_status: :pending,

      # Snapshot — see invariants above.
      customer_name: cart.customer_name,
      customer_email: cart.customer_email,
      gift: cart.gift,
      card_message: cart.card_message,
      recipient_name: cart.recipient_name,
      recipient_phone_number: cart.recipient_phone_number,
      delivery_address: cart.delivery_address,
      delivery_instructions: cart.delivery_instructions,
      fulfillment_date: cart.fulfillment_date,
      fulfillment_amount: cart.fulfillment_amount,
      fulfillment_method: cart.fulfillment_method,
      geocoded_address: cart.geocoded_address,
      here_id: cart.here_id,
      distance: cart.distance,
      position: cart.position,
      locale: cart.locale,

      # Calculated/aggregated snapshots
      line_total: cart.line_total || Decimal.new(0),
      line_tax_amount: cart.line_tax_amount || Decimal.new(0),
      discount_amount: cart.discount_amount || Decimal.new(0),
      fulfillment_tax_amount: cart.fulfillment_tax_amount || Decimal.new(0),
      tax_amount: cart.tax_amount || Decimal.new(0),
      total: cart.total || Decimal.new(0),

      # Reference, not a snapshot — promotion details (code, percentage) are
      # incidental on the order; what matters financially is the
      # discount_amount above. Keeping the FK for reporting (which promotions
      # converted) is cheap.
      promotion_id: cart.promotion_id,
      fulfillment_option_id: cart.fulfillment_option_id
    }
  end

  defp snapshot_line_items(cart, order) do
    cart.line_items
    |> Enum.map(&load_with_line_total/1)
    |> Enum.reduce_while({:ok, []}, fn cart_item, {:ok, acc} ->
      attrs = %{
        order_id: order.id,
        product_id: cart_item.product_id,
        product_variant_id: cart_item.product_variant_id,
        quantity: cart_item.quantity,
        unit_price: cart_item.unit_price,
        tax_rate: cart_item.tax_rate,
        product_name: cart_item.product_name,
        product_image_slug: cart_item.product_image_slug,
        is_card: cart_item.is_card,
        card_size: cart_item.card_size,
        # Snapshot the *computed* line totals so a later promotion edit can't
        # change history.
        line_total: cart_item.line_total,
        discount_amount: cart_item.discount_amount,
        line_tax_amount: cart_item.line_tax_amount
      }

      OrderLineItem
      |> Ash.Changeset.for_create(:snapshot_from_cart, attrs)
      |> Ash.create(actor: system_actor(), authorize?: false)
      |> case do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp load_with_line_total(%CartLineItem{} = item) do
    Ash.load!(
      item,
      [:line_total, :discount_amount, :line_tax_amount],
      authorize?: false,
      lazy?: true
    )
  end
end
