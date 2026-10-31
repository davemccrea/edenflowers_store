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

  # Runs after the drop's rollback re-adds the empty column. A free-delivery fee
  # that is only partly free can't be expressed as in_free_delivery_zone, so
  # those orders read as their full fee; restore a dump (`just rollback`) to
  # keep them exact.
  def down do
    execute """
    UPDATE orders
    SET in_free_delivery_zone = (quoted_free_delivery_fee = 0)
    WHERE quoted_free_delivery_fee IS NOT NULL
    """
  end
end
