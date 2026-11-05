defmodule Edenflowers.Payments.Calculations.RefundMethods do
  @moduledoc """
  The methods Jennie can hand money back by: Stripe while money paid through
  it is still held, the Gift voucher while money it paid is, and any method
  Jennie takes in person while money paid that way is. Nothing when nothing
  is held. `Validations.Refundable` refuses the rest.
  """
  use Ash.Resource.Calculation

  alias Edenflowers.Payments.PaymentMethod

  @impl true
  def load(_query, _opts, _context), do: [:paid_through_stripe, :paid_outside_stripe, :paid_by_voucher]

  @impl true
  def calculate(records, _opts, _context), do: Enum.map(records, &methods/1)

  defp methods(record) do
    stripe = if Decimal.positive?(record.paid_through_stripe), do: [:stripe], else: []
    voucher = if Decimal.positive?(record.paid_by_voucher), do: [:voucher], else: []

    in_person =
      if Decimal.positive?(record.paid_outside_stripe), do: PaymentMethod.values() -- [:stripe, :voucher], else: []

    stripe ++ voucher ++ in_person
  end
end
