defmodule Edenflowers.Repo.Migrations.AddOrderSnapshotFields do
  @moduledoc """
  Snapshot columns on `orders` and `line_items`. See ADR-0001.
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
