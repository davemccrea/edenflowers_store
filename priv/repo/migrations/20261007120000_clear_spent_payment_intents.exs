defmodule Edenflowers.Repo.Migrations.ClearSpentPaymentIntents do
  @moduledoc """
  finalize_checkout used to leave the paid PaymentIntent on the order. Clears
  the ones already recorded as payments; an edited order's payment link may
  still be waiting on its own, which stays.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE orders o SET payment_intent_id = NULL
    WHERE EXISTS (SELECT 1 FROM payments p WHERE p.payment_intent_id = o.payment_intent_id)
    """)
  end

  def down, do: :ok
end
