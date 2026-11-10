defmodule Edenflowers.Courses.Calculations.RegistrationPaymentInstruction do
  @moduledoc """
  How the customer should pay the booking's remaining balance: by invoice, an
  open payment link, or at the course. Nil once the balance is paid.

  Computed in Elixir from the loaded Balance so the SQL doesn't repeat the
  Balance chain and the payable check.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:balance, :payment_link_open?]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      cond do
        Decimal.lte?(record.balance, 0) -> nil
        record.payment_terms == :invoice -> :invoice
        record.payment_link_open? -> :pay_now
        true -> :at_course
      end
    end)
  end
end
