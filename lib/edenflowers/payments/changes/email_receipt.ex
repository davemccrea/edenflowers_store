defmodule Edenflowers.Payments.Changes.EmailReceipt do
  @moduledoc """
  Emails Payment received for a payment Jennie records, when she ticks it.
  Sent once the payment is committed, so a failed email never loses it; the
  result's `:receipt_emailed?` metadata says whether it went.
  """
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      changeset, {:ok, record} -> {:ok, Ash.Resource.put_metadata(record, :receipt_emailed?, email(record, changeset))}
      _changeset, error -> error
    end)
  end

  defp email(record, changeset) do
    arguments = %{amount: changeset.arguments.amount, message: changeset.arguments[:message]}

    case Ash.update(record, arguments, action: :send_payment_received_email, authorize?: false) do
      {:ok, _emailed} ->
        true

      {:error, error} ->
        Logger.error("Receipt for #{inspect(record.__struct__)} #{record.id} not emailed: #{inspect(error)}")
        false
    end
  end
end
