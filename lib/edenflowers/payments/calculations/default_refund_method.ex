defmodule Edenflowers.Payments.Calculations.DefaultRefundMethod do
  @moduledoc """
  Selects the refund form's initial method. Stripe takes priority when it is
  available; otherwise, use the non-Stripe method with the largest net payment
  total, including vouchers. This defaults cash payments back to cash, for
  example. Returns nil when no refund method is available.
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
