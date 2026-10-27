defmodule Edenflowers.Orders.Order.Actions.PrepareCheckoutPayment do
  @moduledoc """
  Readies a cart's PaymentIntent for the customer to pay, from the cart as it
  is now rather than as the checkout page last read it. Refuses a cart that
  was placed meanwhile, is no longer ready for payment, holds only add-ons or
  cards, wants more than is in stock, or has an unavailable fulfillment date,
  with `Payments.Errors.NotPayable`.

  The actor decides the saved cards, so it must be the customer, or nil for a
  guest.
  """

  use Ash.Resource.Actions.Implementation

  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Availability
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments
  alias Edenflowers.Payments.Errors.NotPayable

  @impl true
  def run(input, _opts, context) do
    with {:ok, order} <-
           Orders.get_order_for_checkout(input.arguments.order_id,
             actor: context.actor,
             load: [:checkout_ready?, line_items: [:over_stock?, :product_variant]]
           ),
         :ok <- payable(order),
         :ok <- fulfillment_available(order),
         {:ok, order, client_secret} <- Payments.prepare(order, context.actor) do
      {:ok, %{payable: order, client_secret: client_secret}}
    end
  end

  defp payable(order) do
    cond do
      order.state not in Order.checkout_states() -> {:error, NotPayable.exception(reason: :not_a_cart)}
      order.cart_effectively_empty? -> {:error, NotPayable.exception(reason: :empty_cart)}
      order.add_ons_only? -> {:error, NotPayable.exception(reason: :add_ons_only)}
      not order.checkout_ready? -> {:error, NotPayable.exception(reason: :checkout_not_ready)}
      true -> within_stock(order)
    end
  end

  defp fulfillment_available(order) do
    calendar = Fulfillment.get_shop_calendar!(authorize?: false)

    case Availability.unavailable_reason(calendar, order.fulfillment_date, Edenflowers.ShopTime.now()) do
      nil -> :ok
      _reason -> {:error, NotPayable.exception(reason: :fulfillment_unavailable)}
    end
  end

  defp within_stock(order) do
    case Enum.filter(order.line_items, & &1.over_stock?) do
      [] -> :ok
      line_items -> {:error, NotPayable.exception(reason: :over_stock, line_items: line_items)}
    end
  end
end
