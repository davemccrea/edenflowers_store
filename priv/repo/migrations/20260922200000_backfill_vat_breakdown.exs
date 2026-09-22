defmodule Edenflowers.Repo.Migrations.BackfillVatBreakdown do
  use Ecto.Migration

  require Ash.Query

  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Order.Calculations.Vat

  # Orders placed before `vat_breakdown` existed. Every input to the breakdown
  # (unit prices, tax rates, discount rate, fulfillment fee) is persisted on the
  # order, so recomputing now gives the same rows the snapshot would have held.
  def up do
    Order
    |> Ash.Query.filter(state == :placed and is_nil(vat_breakdown))
    |> Ash.Query.load(Vat.load(nil, nil, nil))
    |> Ash.read!(authorize?: false)
    |> Enum.each(fn order ->
      rows = Vat.breakdown(%{order | state: nil})

      repo().query!("UPDATE orders SET vat_breakdown = $1 WHERE id = $2", [
        rows,
        Ecto.UUID.dump!(order.id)
      ])
    end)
  end

  def down, do: :ok
end
