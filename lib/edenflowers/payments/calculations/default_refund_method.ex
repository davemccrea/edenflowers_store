defmodule Edenflowers.Payments.Calculations.DefaultRefundMethod do
  @moduledoc """
  Which of the `refund_methods` a refund starts at: Stripe when it's one,
  otherwise the method holding the most of the money paid outside Stripe, so
  cash taken is handed back as cash. Nil when nothing can be refunded.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:refund_methods, payments: [:method, :amount]]

  @impl true
  def calculate(records, _opts, _context), do: Enum.map(records, &default/1)

  defp default(%{refund_methods: []}), do: nil

  defp default(record) do
    if :stripe in record.refund_methods, do: :stripe, else: most_held_outside_stripe(record.payments)
  end

  defp most_held_outside_stripe(payments) do
    payments
    |> Enum.reject(&(&1.method == :stripe))
    |> Enum.group_by(& &1.method, & &1.amount)
    |> Enum.map(fn {method, amounts} -> {method, Enum.reduce(amounts, &Decimal.add/2)} end)
    |> Enum.max_by(fn {_method, held} -> held end, Decimal)
    |> elem(0)
  end
end
