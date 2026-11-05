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
  alias Edenflowers.Payments.Validations.Issuable
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
    with [] <- Issuable.errors(invoice),
         {:ok, snapshot} <- InvoiceFinancials.build(invoice.lines),
         :ok <- validate_order(invoice.order_id, Decimal.new(snapshot["gross"])) do
      number = NumberSeries.take()
      today = ShopTime.today()
      seller = Invoice.seller() |> Map.new(fn {key, value} -> {to_string(key), value} end)

      changeset
      |> Ash.Changeset.force_change_attributes(%{
        issued_at: DateTime.utc_now(),
        invoice_date: today,
        due_date: due_date_if_issued(invoice, today),
        number: number,
        reference_number: ReferenceNumber.from_invoice_number(number),
        amount: Decimal.new(snapshot["gross"]),
        financial_snapshot: snapshot,
        lines: Enum.map(snapshot["lines"], &Map.take(&1, ["description", "quantity", "unit_price", "vat_rate"])),
        seller_snapshot: Map.put(seller, "late_interest_rate", Decimal.to_string(Invoice.late_interest_rate(), :normal))
      })
    else
      [_ | _] = field_errors -> Ash.Changeset.add_error(changeset, field_errors)
      {:error, message} -> Ash.Changeset.add_error(changeset, message)
    end
  end

  defp due_date_if_issued(invoice, today),
    do: Ash.load!(invoice, [due_date_if_issued: %{issued_on: today}], authorize?: false).due_date_if_issued

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
end
