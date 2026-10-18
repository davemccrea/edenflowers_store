defmodule Edenflowers.Payments.Changes.EmailReceipt do
  @moduledoc """
  Emails the receipt when the payment Jennie records settles the order or
  booking. Sent once the payment is committed, so a failed email never loses
  it; the result's `:receipt_emailed?` metadata says whether it went.
  """
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      changeset, {:ok, record} -> {:ok, email_if_settled(record, Ash.Changeset.get_argument(changeset, :amount))}
      _changeset, error -> error
    end)
  end

  # A refund that brings the balance to 0 settles it too, but has no receipt.
  defp email_if_settled(record, amount) do
    if Decimal.positive?(amount) and Decimal.eq?(record.balance, 0) do
      Ash.Resource.put_metadata(record, :receipt_emailed?, email(record))
    else
      record
    end
  end

  defp email(record) do
    case Ash.update(record, %{}, action: :email_receipt, authorize?: false) do
      {:ok, _emailed} ->
        true

      {:error, error} ->
        Logger.error("Receipt for #{inspect(record.__struct__)} #{record.id} not emailed: #{inspect(error)}")
        false
    end
  end
end
