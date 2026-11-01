defmodule Edenflowers.Payments.Changes.SendNewInvoice do
  @moduledoc """
  Sends a new invoice through `:send` once it is committed, when Jennie
  ticked to email it. A failed email never loses the invoice or its number;
  the result's `:emailed?` metadata says whether it went.
  """
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.get_argument(changeset, :email_customer?) do
      Ash.Changeset.after_transaction(changeset, fn
        changeset, {:ok, invoice} -> {:ok, send_invoice(invoice, Ash.Changeset.get_argument(changeset, :message))}
        _changeset, error -> error
      end)
    else
      changeset
    end
  end

  defp send_invoice(invoice, message) do
    case Ash.update(invoice, %{message: message}, action: :send, authorize?: false) do
      {:ok, sent} ->
        Ash.Resource.put_metadata(sent, :emailed?, true)

      {:error, error} ->
        Logger.error("Invoice #{invoice.number} (#{invoice.id}) not emailed: #{inspect(error)}")
        Ash.Resource.put_metadata(invoice, :emailed?, false)
    end
  end
end
