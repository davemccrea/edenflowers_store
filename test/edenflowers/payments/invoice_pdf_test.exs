defmodule Edenflowers.Payments.InvoicePdfTest do
  use Edenflowers.DataCase, async: true

  alias Edenflowers.Payments.CreditNote
  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.InvoiceFinancials
  alias Edenflowers.Payments.InvoiceLine
  alias Edenflowers.Payments.InvoicePdf
  alias Edenflowers.Payments.ReferenceNumber

  test "each ordinary wedding invoice prints only its own lines and VAT" do
    booking = issued("Booking advance", "300.00")
    remainder = issued("Wedding flowers remaining charges", "780.00")

    for {invoice, description, amount} <- [
          {booking, "Booking advance", "300,00"},
          {remainder, "Wedding flowers remaining charges", "780,00"}
        ] do
      payload = InvoicePdf.payload(invoice)
      assert [%{"product_name" => ^description}] = payload["line_items"]
      assert payload["amount"] =~ amount
      assert [%{"gross" => gross}] = payload["vat_breakdown"]
      assert gross == payload["amount"]
      refute Map.has_key?(payload, "earlier_invoices")
      refute Map.has_key?(payload, "remainder")
    end
  end

  test "credit note negates exact frozen financial amounts at every VAT rate" do
    invoice =
      issued("Flowers", "100.01", [
        %{"description" => "Service", "quantity" => "3", "unit_price" => "7.23", "vat_rate" => "14"}
      ])

    payload = InvoicePdf.build_payload(%CreditNote{number: 1338, credit_date: ~D[2026-11-02], invoice: invoice})
    assert payload.invoice_number == invoice.number
    assert payload.invoice_date == invoice.content["invoice_date"]
    assert payload.buyer == invoice.content["buyer"]

    for {row, original} <- Enum.zip(payload.vat_breakdown, invoice.financial_snapshot["vat_breakdown"]) do
      assert row.base == Edenflowers.Format.currency(Decimal.negate(Decimal.new(original["base"])), invoice.locale)
      assert row.tax == Edenflowers.Format.currency(Decimal.negate(Decimal.new(original["vat"])), invoice.locale)
      assert row.gross == Edenflowers.Format.currency(Decimal.negate(Decimal.new(original["gross"])), invoice.locale)
    end
  end

  test "render payload remains frozen and uses localized labels and filenames" do
    for {locale, name} <- [{"fi", "lasku"}, {"sv-FI", "faktura"}, {"en-GB", "invoice"}] do
      invoice = issued("Bespoke flowers", "300.00", [], locale)
      before = InvoicePdf.payload(invoice)
      assert InvoicePdf.payload(%{invoice | buyer_name: "Changed", lines: []}) == before
      assert InvoicePdf.filename(invoice) == "#{name}-1337.pdf"
      assert before["seller"]["name"] == "Frozen seller"
      assert before["supply_date"] == nil
      assert byte_size(before["virtual_barcode"]) == 54
    end
  end

  test "a part-paid invoice keeps its total and asks only for what is left" do
    invoice = issued("Wedding flowers", "500.00")
    full = InvoicePdf.payload(%{invoice | amount_paid: Decimal.new(0), amount_unpaid: Decimal.new("500.00")})
    refute Map.has_key?(full, "left_to_pay")

    payload = InvoicePdf.payload(%{invoice | amount_paid: Decimal.new("200.00"), amount_unpaid: Decimal.new("300.00")})
    assert payload["amount"] == full["amount"]
    assert payload["paid"] =~ "200,00"
    assert payload["left_to_pay"] =~ "300,00"
    # Positions 18–25 carry the amount in cents.
    assert binary_part(payload["virtual_barcode"], 17, 8) == "00030000"
    assert binary_part(full["virtual_barcode"], 17, 8) == "00050000"
  end

  test "unit prices print with VAT as typed and without VAT in cents, as on orders" do
    invoice = issued("Small supplies", "0.005")
    assert [%{"unit_price_incl_tax" => incl, "unit_price_ex_tax" => excl}] = invoice.content["line_items"]
    assert incl == "0,005 €"
    assert excl == "0,00 €"
    assert [%{"unit_price_ex_tax" => "239,04 €"}] = issued("Flowers", "300.00").content["line_items"]
    assert InvoicePdf.payload(invoice)["labels"]["unit-price-incl-vat"] == "Verollinen à-hinta"
  end

  test "drafts cannot be rendered as numbered official PDFs" do
    assert {:error, :draft_invoice} = InvoicePdf.issued(%Invoice{})
  end

  @tag :typst
  test "invoice and complete credit PDF render in all three languages" do
    for locale <- ["fi", "sv-FI", "en-GB"] do
      invoice = issued("Bespoke flowers", "300.00", [], locale)
      assert {:ok, <<"%PDF-", _::binary>>} = InvoicePdf.render(invoice)
      # Render directly because this test has no persisted invoice relationship.
      note = %CreditNote{number: 1338, credit_date: ~D[2026-11-02], invoice: invoice}

      assert {:ok, <<"%PDF-", _::binary>>} =
               InvoicePdf.render(note)
    end
  end

  defp issued(description, price, extra \\ [], locale \\ "fi") do
    {:ok, snapshot} =
      [%{"description" => description, "quantity" => "1", "unit_price" => price, "vat_rate" => "25.5"} | extra]
      |> Enum.map(&invoice_line/1)
      |> InvoiceFinancials.build()

    invoice = %Invoice{
      number: 1337,
      issued_at: ~U[2026-11-02 10:00:00.000000Z],
      locale: locale,
      reference_number: ReferenceNumber.from_invoice_number(1337),
      amount: Decimal.new(snapshot["gross"]),
      invoice_date: ~D[2026-11-02],
      due_date: ~D[2026-11-16],
      buyer_name: "Buyer",
      buyer_email: "buyer@example.com",
      buyer_address: "Address",
      business_customer: false,
      financial_snapshot: snapshot,
      seller_snapshot: %{
        "name" => "Frozen seller",
        "business_id" => "1234567-1",
        "address" => "Seller address",
        "iban" => Invoice.seller().iban,
        "late_interest_rate" => "0.08"
      }
    }

    {:ok, content} = InvoicePdf.content(invoice)
    %{invoice | content: content}
  end

  defp invoice_line(line) do
    %InvoiceLine{
      description: line["description"],
      quantity: Decimal.new(line["quantity"]),
      unit_price: Decimal.new(line["unit_price"]),
      vat_rate: Decimal.new(line["vat_rate"])
    }
  end
end
