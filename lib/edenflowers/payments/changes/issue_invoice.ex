defmodule Edenflowers.Payments.Changes.IssueInvoice do
  @moduledoc "Validates and freezes a standalone draft under its row lock before taking the shared document number."
  use Ash.Resource.Change

  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.InvoiceFinancials
  alias Edenflowers.Payments.NumberSeries
  alias Edenflowers.Payments.ReferenceNumber

  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &issue/1)
  end

  defp issue(changeset) do
    invoice = Invoice.get_locked(changeset.data.id, [])

    cond do
      is_nil(invoice) -> Ash.Changeset.add_error(changeset, "Invoice no longer exists")
      invoice.issued_at -> Ash.Changeset.add_error(changeset, "Invoice has already been issued")
      true -> freeze(%{changeset | data: invoice}, invoice)
    end
  end

  defp freeze(changeset, invoice) do
    with :ok <- validate_buyer(invoice),
         true <- Date.compare(invoice.due_date, invoice.invoice_date) != :lt,
         {:ok, snapshot} <- InvoiceFinancials.build(invoice.lines) do
      number = NumberSeries.take()
      seller = Invoice.seller() |> Map.new(fn {key, value} -> {to_string(key), value} end)

      changeset
      |> Ash.Changeset.force_change_attributes(%{
        issued_at: DateTime.utc_now(),
        number: number,
        reference_number: ReferenceNumber.from_invoice_number(number),
        amount: Decimal.new(snapshot["gross"]),
        financial_snapshot: snapshot,
        lines: Enum.map(snapshot["lines"], &Map.take(&1, ["description", "quantity", "unit_price", "vat_rate"])),
        seller_snapshot: Map.put(seller, "late_interest_rate", Decimal.to_string(Invoice.late_interest_rate(), :normal))
      })
    else
      false -> Ash.Changeset.add_error(changeset, field: :due_date, message: "cannot be before the invoice date")
      {:error, message} -> Ash.Changeset.add_error(changeset, message)
    end
  end

  defp validate_buyer(invoice) do
    fields = [:buyer_name, :buyer_email] ++ address_fields(invoice)

    complete? =
      Enum.all?(fields, fn field ->
        value = Map.get(invoice, field)
        is_binary(value) and String.trim(value) != ""
      end)

    if complete?,
      do: :ok,
      else: {:error, "Complete the buyer name, email and postal address (and company details for businesses)"}
  end

  defp address_fields(%{business_customer: true}), do: [:company_name, :business_id, :billing_address]
  defp address_fields(_invoice), do: [:buyer_address]
end
