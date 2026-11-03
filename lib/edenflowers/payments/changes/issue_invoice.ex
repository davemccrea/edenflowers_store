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
    with :ok <- validate_fields(invoice),
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
      {:error, message} -> Ash.Changeset.add_error(changeset, message)
    end
  end

  @doc "Field errors for issuance, also shown by the admin editor after a failed issue."
  def field_errors(invoice) do
    required = [:buyer_name, :buyer_email] ++ address_fields(invoice)

    buyer_errors =
      Enum.flat_map(required, fn field ->
        value = Map.get(invoice, field)

        if is_binary(value) and String.trim(value) != "",
          do: [],
          else: [[field: field, message: "can't be blank"]]
      end)

    date_errors =
      if match?(%Date{}, invoice.due_date) and match?(%Date{}, invoice.invoice_date) and
           Date.compare(invoice.due_date, invoice.invoice_date) == :lt,
         do: [[field: :due_date, message: "cannot be before the invoice date"]],
         else: []

    Enum.map(buyer_errors ++ date_errors ++ line_errors(invoice.lines), &Ash.Error.Changes.InvalidAttribute.exception/1)
  end

  # A draft's line may be unfinished; an issued one prints every field.
  defp line_errors(lines) do
    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, index} ->
      for field <- [:description, :quantity, :unit_price, :vat_rate],
          blank?(Map.get(line, field)),
          do: [field: field, path: [:lines, index], message: "can't be blank"]
    end)
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(value), do: is_nil(value)

  defp validate_fields(invoice) do
    case field_errors(invoice) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp address_fields(%{business_customer: true}), do: [:company_name, :business_id, :billing_address]
  defp address_fields(_invoice), do: [:buyer_address]
end
