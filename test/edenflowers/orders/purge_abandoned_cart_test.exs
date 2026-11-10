defmodule Edenflowers.Orders.PurgeAbandonedCartTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Ecto.Adapters.SQL
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Schedulers.PurgeAbandonedCart, as: SchedulePurge
  alias Edenflowers.Orders.Workers.PurgeAbandonedCart, as: Purge

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days, :day)

  test "purges empty carts left for over a day, keeping anything with items or a payment" do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id))

    abandoned = generate(order(updated_at: days_ago(2)))
    fresh = generate(order())
    with_items = generate(order(updated_at: days_ago(2)))
    generate(line_item(order_id: with_items.id, product_variant_id: variant.id))

    SQL.query!(Edenflowers.Repo, "UPDATE orders SET updated_at = $1 WHERE id = $2", [
      days_ago(2),
      Ecto.UUID.dump!(with_items.id)
    ])

    with_payment = generate(order(updated_at: days_ago(2), payment_intent_id: "pi_in_flight"))

    # A code from a link waits on an empty cart for the visitor to choose flowers.
    promotion = generate(promotion())
    with_code = generate(order(updated_at: days_ago(2), promotion_id: promotion.id))
    with_old_code = generate(order(updated_at: days_ago(31), promotion_id: promotion.id))

    assert :ok = perform_job(SchedulePurge, %{})

    for %{args: args} <- all_enqueued(worker: Purge), do: perform_job(Purge, args)

    ids = Order |> Ash.read!(authorize?: false) |> Enum.map(& &1.id)
    refute abandoned.id in ids
    assert fresh.id in ids
    assert with_items.id in ids
    assert with_payment.id in ids
    assert with_code.id in ids
    refute with_old_code.id in ids
  end

  test "purges a cart holding items and contact details only after 90 days" do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id))

    stale_cart = fn attrs, days ->
      order = generate(order(attrs))
      generate(line_item(order_id: order.id, product_variant_id: variant.id))

      SQL.query!(Edenflowers.Repo, "UPDATE orders SET updated_at = $1 WHERE id = $2", [
        days_ago(days),
        Ecto.UUID.dump!(order.id)
      ])

      order
    end

    contact = [customer_name: "Ada Lovelace", customer_email: "ada@example.com", customer_phone: "+358401234567"]

    old = stale_cart.(contact, 91)
    recent = stale_cart.(contact, 89)
    in_flight = stale_cart.([payment_intent_id: "pi_in_flight"] ++ contact, 91)
    placed = stale_cart.([state: :placed] ++ contact, 91)

    assert :ok = perform_job(SchedulePurge, %{})

    for %{args: args} <- all_enqueued(worker: Purge), do: perform_job(Purge, args)

    ids = Order |> Ash.read!(authorize?: false) |> Enum.map(& &1.id)
    refute old.id in ids
    assert recent.id in ids
    assert in_flight.id in ids
    assert placed.id in ids
  end
end
