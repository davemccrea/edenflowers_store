defmodule Edenflowers.Payments.StandaloneInvoiceDocumentsTest do
  use Edenflowers.DataCase, async: true
  import Generator
  alias Edenflowers.Email
  alias Edenflowers.Payments
  alias Edenflowers.Payments.Changes.SendInvoice
  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.InvoicePdf

  setup do
    admin = generate(admin_user())

    {:ok, draft} =
      Payments.create_invoice(
        %{
          buyer_name: "Emma Buyer",
          buyer_email: "emma@example.com",
          supply_date: ~D[2026-11-02],
          locale: "en-GB",
          lines: [%{description: "Wedding booking advance", quantity: "1", unit_price: "300", vat_rate: "25.5"}]
        },
        actor: admin
      )

    %{admin: admin, draft: draft}
  end

  test "draft cannot be sent, downloaded or credited", %{admin: admin, draft: draft} do
    assert {:error, error} = Payments.send_invoice(draft, %{}, actor: admin)
    assert Exception.message(error) =~ "Issue this invoice before sending it."
    assert {:error, :draft_invoice} = InvoicePdf.issued(draft)
    assert {:error, _} = Payments.cancel_invoice(%{invoice_id: draft.id}, actor: admin)
  end

  test "standalone email and preview use invoice buyer and own amount", %{admin: admin, draft: draft} do
    {:ok, invoice} = Payments.issue_invoice(draft, actor: admin)
    email = invoice |> SendInvoice.load_for_email() |> Email.invoice()
    assert email.to == [{"", "emma@example.com"}]
    assert email.subject == "Invoice #{invoice.number}"
    assert email.text_body =~ "Invoice #{invoice.number} is attached."
    refute email.text_body =~ "Amount due"
    refute email.text_body =~ "Due date"
    refute email.text_body =~ "IBAN"
    refute email.text_body =~ "Reference number"
    refute email.text_body =~ "of the"
    preview = Edenflowers.Email.Preview.build_invoice(invoice)
    assert preview.subject == email.subject
    assert preview.text_body == email.text_body
  end

  test "a partly paid invoice still states the outstanding balance", %{admin: admin, draft: draft} do
    {:ok, invoice} = Payments.issue_invoice(draft, actor: admin)
    {:ok, invoice} = Payments.record_invoice_payment(invoice, "100", %{}, actor: admin)
    email = invoice |> SendInvoice.load_for_email() |> Email.invoice()
    remaining = Edenflowers.Format.currency(Decimal.new("200"), invoice.locale)
    assert email.text_body =~ "There is #{remaining} still to pay."
    refute email.text_body =~ "IBAN"
  end

  @tag :typst
  test "failed sends preserve issuance and can retry the issued document as a reminder", %{admin: admin, draft: draft} do
    {:ok, invoice} = Payments.issue_invoice(draft, actor: admin)
    invoice = Ash.Seed.update!(invoice, %{invoice_date: ~D[2025-01-01], due_date: ~D[2025-01-15]})
    original = Ash.load!(invoice, :pdf, authorize?: false).pdf
    broken = Ash.Seed.update!(invoice, %{pdf: nil})
    assert {:error, _} = Payments.send_invoice(broken, %{}, actor: admin)
    persisted = Ash.get!(Invoice, invoice.id, authorize?: false)
    assert persisted.issued_at == invoice.issued_at
    assert persisted.number == invoice.number
    assert persisted.sent_at == nil
    restored = Ash.Seed.update!(persisted, %{pdf: original})
    assert {:ok, sent} = Payments.send_invoice(restored, %{}, actor: admin)
    assert sent.sent_at

    Swoosh.TestAssertions.assert_email_sent(fn email ->
      assert email.subject =~ "A reminder about invoice"
      assert email.text_body =~ "friendly reminder"
      assert [%{filename: filename, data: ^original}] = email.attachments
      assert filename == "invoice-#{invoice.number}.pdf"
    end)
  end

  @tag :typst
  test "the issued PDFs are kept, so later changes never alter what the books hold", %{admin: admin, draft: draft} do
    {:ok, invoice} = Payments.issue_invoice(draft, actor: admin)
    {:ok, issued_pdf} = InvoicePdf.issued(invoice)
    assert <<"%PDF-", _::binary>> = issued_pdf
    # Stands in for a template or translation change after issuance.
    changed = Ash.Seed.update!(invoice, %{content: put_in(invoice.content, ["buyer", "name"], "Someone else")})
    assert InvoicePdf.issued(changed) == {:ok, issued_pdf}
    assert InvoicePdf.for_email(changed) == {:ok, issued_pdf}

    {:ok, part_paid} = Payments.record_invoice_payment(invoice, "100", %{}, actor: admin)
    assert {:ok, reminder_pdf} = InvoicePdf.for_email(part_paid)
    refute reminder_pdf == issued_pdf
    assert InvoicePdf.issued(part_paid) == {:ok, issued_pdf}
  end

  @tag :typst
  test "a credit note's PDF is kept as made", %{admin: admin, draft: draft} do
    {:ok, invoice} = Payments.issue_invoice(draft, actor: admin)
    {:ok, credit} = Payments.cancel_invoice(%{invoice_id: invoice.id}, actor: admin)
    {:ok, pdf} = InvoicePdf.issued(credit)
    Ash.Seed.update!(invoice, %{content: put_in(invoice.content, ["buyer", "name"], "Someone else")})
    assert InvoicePdf.issued(Ash.get!(Payments.CreditNote, credit.id, authorize?: false)) == {:ok, pdf}
  end

  test "full credit is created without changing immutable invoice financials", %{admin: admin, draft: draft} do
    {:ok, invoice} = Payments.issue_invoice(draft, actor: admin)
    {:ok, credit} = Payments.cancel_invoice(%{invoice_id: invoice.id}, actor: admin)
    credit = Ash.load!(credit, :invoice, authorize?: false)
    payload = InvoicePdf.build_payload(credit)
    assert payload.amount == Edenflowers.Format.currency(Decimal.negate(invoice.amount), credit.invoice.locale)
    reread = Ash.get!(Invoice, invoice.id, authorize?: false)
    assert reread.financial_snapshot == invoice.financial_snapshot
    assert {:error, _} = Payments.cancel_invoice(%{invoice_id: invoice.id}, actor: admin)
  end
end
