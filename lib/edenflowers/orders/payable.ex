defmodule Edenflowers.Orders.Payable do
  @moduledoc "An order, as `Edenflowers.Payments` takes payment for it."

  @behaviour Edenflowers.Payments.Payable

  import Edenflowers.Actors

  alias Edenflowers.Orders

  @impl true
  def metadata_key, do: "order_id"

  @impl true
  def expected_amount(order), do: order.grand_total

  @impl true
  def add_payment_intent_id(order, payment_intent_id, actor) do
    Orders.add_payment_intent_id(order, payment_intent_id, actor: actor)
  end

  @impl true
  def complete(id, payment_intent_id, amount_paid) do
    Orders.finalize_checkout(id, payment_intent_id, %{amount_paid: amount_paid}, actor: system_actor())
  end

  @impl true
  def fail(id, payment_intent_id) do
    Orders.mark_payment_failed(id, payment_intent_id, actor: system_actor())
  end

  @impl true
  def awaiting_payment(settled_before, abandoned_before) do
    Orders.list_orders_awaiting_payment!(settled_before, abandoned_before, actor: system_actor())
  end
end
