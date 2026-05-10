defmodule Edenflowers.Repo.Migrations.AddOrderSnapshotFields do
  @moduledoc """
  Adds snapshot fields to `orders` and `line_items` for the Spree-style
  immutable-after-place model. See ADR-0001.

    * `orders.fulfillment_tax_rate` — denormalised at submit_delivery so a
      later edit to the option's tax_rate (e.g. Finland VAT change) cannot
      retroactively alter what this order was quoted/charged.
    * `orders.placed_*` — captured at finalize_checkout from live
      aggregates/calculations. Authoritative for placed orders.
    * `line_items.placed_*` — captured at the parent order's
      finalize_checkout from live calculations.

  All columns nullable: cart-state rows have them as NULL; placed rows have
  them populated. Lockdown is enforced at the resource policy layer; the
  database doesn't need a CHECK because the only writers are the snapshot
  change and admin-only post-place actions.
  """

  use Ecto.Migration

  def up do
    alter table(:orders) do
      add :fulfillment_tax_rate, :decimal
      add :placed_line_total, :decimal
      add :placed_line_tax_amount, :decimal
      add :placed_discount_amount, :decimal
      add :placed_fulfillment_tax_amount, :decimal
      add :placed_tax_amount, :decimal
      add :placed_total, :decimal
      add :placed_promotion_code, :text
    end

    alter table(:line_items) do
      add :placed_line_total, :decimal
      add :placed_discount_amount, :decimal
      add :placed_line_tax_amount, :decimal
    end
  end

  def down do
    alter table(:line_items) do
      remove :placed_line_tax_amount
      remove :placed_discount_amount
      remove :placed_line_total
    end

    alter table(:orders) do
      remove :placed_promotion_code
      remove :placed_total
      remove :placed_tax_amount
      remove :placed_fulfillment_tax_amount
      remove :placed_discount_amount
      remove :placed_line_tax_amount
      remove :placed_line_total
      remove :fulfillment_tax_rate
    end
  end
end
