defmodule Edenflowers.Expenses.Calculations.ReviewReasons do
  @moduledoc """
  Why an expense needs Jennie's review, in the order her page lists them. The
  same conditions as the `needs_review` expression, which filters the list.
  """
  use Ash.Resource.Calculation

  @required [
    date: :missing_date,
    vendor_name: :missing_vendor,
    total_amount: :missing_total,
    currency: :missing_currency
  ]

  @impl true
  def load(_query, _opts, _context), do: [:matched_by_amount, :reviewed_at, :sure | Keyword.keys(@required)]

  @impl true
  def calculate(expenses, _opts, _context), do: Enum.map(expenses, &reasons/1)

  defp reasons(expense) do
    payment = if expense.matched_by_amount, do: [:matched_by_amount], else: []

    if is_nil(expense.reviewed_at) do
      missing = for {field, reason} <- @required, is_nil(Map.fetch!(expense, field)), do: reason
      unsure = if expense.sure, do: [], else: [:unsure]
      payment ++ missing ++ unsure
    else
      payment
    end
  end
end
