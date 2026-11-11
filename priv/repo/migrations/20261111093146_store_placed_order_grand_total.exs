defmodule Edenflowers.Repo.Migrations.StorePlacedOrderGrandTotal do
  @moduledoc """
  Stores each placed order's grand total (TASK-188, ADR 0007), backfilled
  from the live calculation before the check constraint requires it.
  """

  use Ecto.Migration

  import Ecto.Query

  require Ash.Query

  def up do
    alter table(:orders) do
      add :stored_grand_total, :decimal
    end

    flush()
    backfill()

    create constraint(:orders, :orders_placed_have_stored_grand_total,
             check: """
               state <> 'placed' OR stored_grand_total IS NOT NULL
             """
           )
  end

  def down do
    drop_if_exists constraint(:orders, :orders_placed_have_stored_grand_total)

    alter table(:orders) do
      remove :stored_grand_total
    end
  end

  # Through Ash, as the grand total's rules live in Order's calculation. A
  # fresh database has no placed orders and skips it, so later changes to
  # Order can't break migrating one. To migrate an older dump once Order's
  # grand total reads a column added later, migrate it with v1.30.4 first.
  defp backfill do
    if repo().exists?(from(o in "orders", where: o.state == "placed")) do
      Edenflowers.Orders.Order
      |> Ash.Query.filter(state == :placed)
      |> Ash.Query.select([:id])
      |> Ash.Query.load(:grand_total)
      |> Ash.read!(authorize?: false)
      |> Enum.each(fn order ->
        from(o in "orders", where: o.id == type(^order.id, :binary_id))
        |> repo().update_all(set: [stored_grand_total: order.grand_total])
      end)
    end
  end
end
