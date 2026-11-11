defmodule Edenflowers.Payments.Calculations.RefundMethods do
  @moduledoc """
  Lists the refund methods available for the money still held on a purchase.
  Stripe and Gift voucher refunds require a remaining payment balance for
  that method. Money paid outside Stripe and vouchers can be returned by any
  of Jennie's in-person methods, not just the method originally recorded.
  Returns an empty list when no money remains. `Validations.Refundable`
  enforces these limits when a refund is submitted.
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
