defmodule Edenflowers.Repo.Migrations.RenameCardSizeToVariantSize do
  use Ecto.Migration

  def up do
    # Clear in-flight carts so pre-checkout line items without a snapshotted
    # variant_size don't render blank. Placed orders are preserved.
    execute("""
    DELETE FROM line_items
    WHERE order_id IN (SELECT id FROM orders WHERE state <> 'placed')
    """)

    rename table(:line_items), :card_size, to: :variant_size
  end

  def down do
    rename table(:line_items), :variant_size, to: :card_size
  end
end
