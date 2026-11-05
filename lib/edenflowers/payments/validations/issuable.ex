defmodule Edenflowers.Payments.Validations.Issuable do
  @moduledoc """
  The fields an invoice must have filled before it can be issued: the buyer,
  a business customer's company details, the date of supply and every field
  of every line. A draft may leave any of them blank.

  `IssueInvoice` checks the locked draft with `errors/1`. The draft actions
  run it as a validation when asked with `check_issue?`, so the editor marks
  the same fields after a failed issue as Jennie corrects them.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    invoice =
      Map.new([:business_customer, :lines | required_fields(true)], fn field ->
        {field, Ash.Changeset.get_attribute(changeset, field)}
      end)

    case errors(invoice) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc "What stops this invoice, or an invoice with these values, from being issued."
  def errors(invoice) do
    field_errors =
      for field <- required_fields(invoice.business_customer),
          blank?(Map.get(invoice, field)),
          do: [field: field, message: "can't be blank"]

    Enum.map(field_errors ++ line_errors(invoice.lines || []), &Ash.Error.Changes.InvalidAttribute.exception/1)
  end

  defp required_fields(true = _business_customer),
    do: [:buyer_name, :buyer_email, :company_name, :business_id, :billing_address, :supply_date]

  defp required_fields(_business_customer), do: [:buyer_name, :buyer_email, :supply_date]

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
end
