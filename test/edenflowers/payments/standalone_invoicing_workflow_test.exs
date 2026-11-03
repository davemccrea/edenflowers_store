defmodule Edenflowers.Payments.StandaloneInvoicingWorkflowTest do
  use Edenflowers.DataCase, async: false
  import Generator

  alias Edenflowers.Payments
  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.InvoicePdf
  alias Edenflowers.Payments.ReferenceNumber

  test "a wedding advance and remainder are independent ordinary invoices with their own VAT and historical balances" do
    admin = generate(admin_user())
    advance = issue(admin, "Wedding booking advance", "100", "25.5", ~D[2026-09-01])
    remainder = issue(admin, "Wedding remaining flowers", "300", "14", ~D[2026-09-01])
    assert ReferenceNumber.valid?(advance.reference_number)
    assert ReferenceNumber.valid?(remainder.reference_number)
    assert advance.number + 1 == remainder.number
    assert advance.financial_snapshot["vat"] == "20.32"
    assert remainder.financial_snapshot["vat"] == "36.84"
    {:ok, settled} = Payments.record_invoice_payment(advance, "100", %{paid_at: ~U[2026-09-10 08:00:00Z]}, actor: admin)
    assert settled.status == :paid
    assert Decimal.equal?(Ash.load!(remainder, :amount_unpaid, authorize?: false).amount_unpaid, "300")

    {:ok, partly_paid} =
      Payments.record_invoice_payment(remainder, "60", %{paid_at: ~U[2026-09-30 20:59:00Z]}, actor: admin)

    assert {:error, _} = Payments.cancel_invoice(%{invoice_id: remainder.id}, actor: admin)
    [receipt] = partly_paid.payments

    {:ok, reopened} =
      Payments.undo_invoice_payment(remainder, receipt.id, %{paid_at: ~U[2026-09-30 21:00:00Z]}, actor: admin)

    assert Decimal.equal?(reopened.amount_unpaid, "300")

    {:ok, [historical]} =
      Payments.list_open_invoices(~D[2026-09-30], load: [amount_open_at: %{date: ~D[2026-09-30]}], actor: admin)

    assert historical.id == remainder.id
    assert Decimal.equal?(historical.amount_open_at, "240")
    assert Ash.load!(advance, :status, authorize?: false).status == :paid

    mistake = issue(admin, "Incorrect separate quote", "10", "25.5", ~D[2026-10-02])
    {:ok, credit} = Payments.cancel_invoice(%{invoice_id: mistake.id}, actor: admin)
    replacement = issue(admin, "Corrected separate quote", "12", "25.5", ~D[2026-10-02])
    assert credit.number + 1 == replacement.number
    assert Ash.get!(Invoice, mistake.id, load: [:status], actor: admin).status == :cancelled
    assert {:ok, <<"%PDF-", _::binary>>} = InvoicePdf.issued(advance)
    assert {:ok, <<"%PDF-", _::binary>>} = InvoicePdf.issued(remainder)
    assert {:ok, <<"%PDF-", _::binary>>} = InvoicePdf.issued(credit)
  end

  defp issue(admin, description, price, rate, date) do
    {:ok, draft} =
      Payments.create_invoice(
        %{
          buyer_name: "Wedding couple",
          buyer_email: "couple@example.com",
          buyer_address: "Street 1, Vaasa",
          customer_reference: "Wedding 2026",
          locale: "sv-FI",
          supply_date: date,
          lines: [%{description: description, quantity: "1", unit_price: price, vat_rate: rate}]
        },
        actor: admin
      )

    {:ok, invoice} = Payments.issue_invoice(draft, actor: admin)

    Ash.Seed.update!(invoice, %{
      issued_at: DateTime.new!(date, ~T[08:00:00]),
      invoice_date: date,
      due_date: Date.add(date, 14)
    })
  end
end
