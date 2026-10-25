defmodule Edenflowers.Payments.Changes.ReportAmountMismatch do
  @moduledoc """
  The customer has paid, so the order is placed or the booking confirmed even
  when Stripe received a different amount, usually because the cart or the
  booking changed while payment was in flight. Logged as an error so it
  reaches ErrorTracker; the admin lists also flag it, as an amount to collect
  or refund.
  """
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      checked = Ash.load!(record, [:total_due, :amount_paid], authorize?: false, reuse_values?: false)

      if not Decimal.eq?(checked.amount_paid, checked.total_due) do
        Logger.error(
          "Amount mismatch for #{Ash.Resource.Info.short_name(record.__struct__)} #{record.id} " <>
            "(expected: #{checked.total_due}, got: #{checked.amount_paid}). " <>
            "Kept it anyway; it likely changed while payment was in flight."
        )
      end

      {:ok, record}
    end)
  end
end
