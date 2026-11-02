defmodule Edenflowers.Payments.Validations.InvoicePayment do
  @moduledoc "Validates invoice-owned ledger rows under the same row lock used by full credits."
  use Ash.Resource.Validation

  alias Edenflowers.Payments.Invoice

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :invoice_id) do
      nil -> :ok
      id -> validate_invoice(Invoice.get_locked(id, [:status]), changeset)
    end
  end

  defp validate_invoice(nil, _), do: {:error, field: :invoice_id, message: "Invoice no longer exists"}

  defp validate_invoice(invoice, changeset) do
    cond do
      Ash.Changeset.get_attribute(changeset, :order_id) ||
          Ash.Changeset.get_attribute(changeset, :course_registration_id) ->
        {:error, field: :invoice_id, message: "Invoice payments belong only to the invoice"}

      invoice.status in [:draft, :cancelled] ->
        {:error, field: :invoice_id, message: "Only issued, uncredited invoices can receive payments"}

      Ash.Changeset.get_attribute(changeset, :method) != :zervant ->
        {:error, field: :method, message: "Invoice payments must be bank transfers"}

      true ->
        :ok
    end
  end
end
