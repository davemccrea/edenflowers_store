defmodule Edenflowers.Orders.PurgeAbandonedCartTest do
  use Edenflowers.DataCase

  import Generator

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

    Ecto.Adapters.SQL.query!(Edenflowers.Repo, "UPDATE orders SET updated_at = $1 WHERE id = $2", [
      days_ago(2),
      Ecto.UUID.dump!(with_items.id)
    ])

    with_payment = generate(order(updated_at: days_ago(2), payment_intent_id: "pi_in_flight"))

    assert :ok = perform_job(SchedulePurge, %{})

    for %{args: args} <- all_enqueued(worker: Purge), do: perform_job(Purge, args)

    ids = Order |> Ash.read!(authorize?: false) |> Enum.map(& &1.id)
    refute abandoned.id in ids
    assert fresh.id in ids
    assert with_items.id in ids
    assert with_payment.id in ids
  end
end
