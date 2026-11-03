defmodule Edenflowers.Payments.Changes.IssueInvoice do
  @moduledoc """
  Validates and freezes a standalone draft under its row lock before taking
  the shared document number. It is dated the day it is issued, in Helsinki,
  and due its payment term later, so its date never falls before an earlier
  number's and a draft left open still gives the customer the whole term.

  An invoice for an order is issued only while that order is `invoiceable?`
  and for exactly its Balance, checked under the order's row lock so two
  drafts for one order can't both be issued. Requiring the exact amount
  refuses a draft left stale by an edit to the order, and never leaves part
  of the Balance that a second invoice could not collect.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  require Ash.Query

  alias Edenflowers.Format
  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.InvoiceFinancials
  alias Edenflowers.Payments.NumberSeries
  alias Edenflowers.Payments.ReferenceNumber
  alias Edenflowers.ShopTime

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
         {:ok, snapshot} <- InvoiceFinancials.build(invoice.lines),
         :ok <- validate_order(invoice.order_id, Decimal.new(snapshot["gross"])) do
      number = NumberSeries.take()
      today = ShopTime.today()
      seller = Invoice.seller() |> Map.new(fn {key, value} -> {to_string(key), value} end)

      changeset
      |> Ash.Changeset.force_change_attributes(%{
        issued_at: DateTime.utc_now(),
        invoice_date: today,
        due_date: Date.add(today, invoice.payment_term_days),
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
    required = [:buyer_name, :buyer_email] ++ address_fields(invoice) ++ [:supply_date]

    field_errors =
      for field <- required,
          blank?(Map.get(invoice, field)),
          do: [field: field, message: "can't be blank"]

    Enum.map(field_errors ++ line_errors(invoice.lines), &Ash.Error.Changes.InvalidAttribute.exception/1)
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

  defp validate_order(nil, _amount), do: :ok

  defp validate_order(order_id, amount) do
    order =
      Order
      |> Ash.Query.filter(id == ^order_id)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)
      |> Ash.load!([:invoiceable?, :balance], authorize?: false)

    cond do
      not order.invoiceable? ->
        {:error, ~t"This order can't be invoiced now: it has a payment or an invoice, or isn't on invoice terms."}

      not Decimal.eq?(amount, order.balance) ->
        {:error,
         ~t"The invoice comes to #{invoiced = Format.currency(amount, Format.locale())}, but the order has #{balance = Format.currency(order.balance, Format.locale())} to collect. Make them match."}

      true ->
        :ok
    end
  end

  defp address_fields(%{business_customer: true}), do: [:company_name, :business_id, :billing_address]
  defp address_fields(_invoice), do: [:buyer_address]
end
