defmodule Edenflowers.Payments.Calculations.RefundMethods do
  @moduledoc """
  The methods Jennie can hand money back by: Stripe while money paid through
  it is still held, and any other method while money paid outside it is.
  Nothing when nothing is held. `Validations.Refundable` refuses the rest.
  """
  use Ash.Resource.Calculation

  alias Edenflowers.Payments.PaymentMethod

  @impl true
  def load(_query, _opts, _context), do: [:paid_through_stripe, :paid_outside_stripe]

  @impl true
  def calculate(records, _opts, _context), do: Enum.map(records, &methods/1)

  defp methods(record) do
    stripe = if Decimal.positive?(record.paid_through_stripe), do: [:stripe], else: []
    outside = if Decimal.positive?(record.paid_outside_stripe), do: PaymentMethod.values() -- [:stripe], else: []
    stripe ++ outside
  end
end
