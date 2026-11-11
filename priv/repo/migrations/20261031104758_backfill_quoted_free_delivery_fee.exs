defmodule Edenflowers.Repo.Migrations.BackfillQuotedFreeDeliveryFee do
  use Ecto.Migration

  # Orders quoted before the first 5 km became free keep the fee they were
  # charged: nothing in the free delivery zone, the full fee outside it.
  def up do
    execute """
    UPDATE orders
    SET quoted_free_delivery_fee =
      CASE WHEN in_free_delivery_zone THEN 0 ELSE quoted_fulfillment_fee END
    WHERE quoted_fulfillment_fee IS NOT NULL
    """
  end

  # The later DropInFreeDeliveryZone migration's rollback restores the empty column first.
  # The old boolean cannot represent a partly waived delivery fee, so those orders
  # revert to their full fee. Restore a database dump with `just rollback` to preserve exact fees.
  def down do
    execute """
    UPDATE orders
    SET in_free_delivery_zone = (quoted_free_delivery_fee = 0)
    WHERE quoted_free_delivery_fee IS NOT NULL
    """
  end
end
