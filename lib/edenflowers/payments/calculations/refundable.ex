defmodule Edenflowers.Payments.Calculations.Refundable do
  @moduledoc """
  Whether Jennie can hand money back now: committed, nothing left to collect,
  money still held, and not something refunded only by cancelling it.

  Computed in Elixir from the loaded values so the SQL doesn't repeat the
  Balance and held-money expressions that the expression version inlined.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context),
    do: [:committed?, :balance, :amount_held, :refunded_only_by_cancelling?]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      record.committed? and Decimal.lte?(record.balance, 0) and
        Decimal.positive?(record.amount_held) and not record.refunded_only_by_cancelling?
    end)
  end
end
