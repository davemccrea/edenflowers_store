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
          buyer_address: "Street 1",
          locale: "en-GB",
          lines: [%{description: "Wedding booking advance", quantity: "1", unit_price: "300", vat_rate: "25.5"}]
        },
        actor: admin
      )

    %{admin: admin, draft: draft}
  end

  test "draft cannot be sent, downloaded or credited", %{admin: admin, draft: draft} do
    assert {:error, _} = Payments.send_invoice(draft, %{}, actor: admin)
    assert {:error, :draft_invoice} = InvoicePdf.generate(draft)
    assert {:error, _} = Payments.cancel_invoice(%{invoice_id: draft.id}, actor: admin)
  end

  test "standalone email and preview use invoice buyer and own amount", %{admin: admin, draft: draft} do
    {:ok, invoice} = Payments.issue_invoice(draft, actor: admin)
    email = invoice |> SendInvoice.load_for_email() |> Email.invoice("Thank you")
    assert email.to == [{"", "emma@example.com"}]
    assert email.subject == "Invoice #{invoice.number}"
    assert email.text_body =~ "My invoice #{invoice.number} is attached."
    assert email.text_body =~ "Thank you"
    refute email.text_body =~ "of the"
    preview = Edenflowers.Email.Preview.build_invoice(invoice, "Preview")
    assert preview.subject == email.subject
    assert preview.text_body =~ "Preview"
  end

  @tag :typst
  test "failed sends preserve issuance and can retry the frozen document as a reminder", %{admin: admin, draft: draft} do
    {:ok, draft} =
      Payments.update_invoice_draft(draft, %{invoice_date: ~D[2025-01-01], due_date: ~D[2025-01-15]}, actor: admin)

    {:ok, invoice} = Payments.issue_invoice(draft, actor: admin)
    original = invoice.content
    broken = Ash.Seed.update!(invoice, %{content: %{}})
    assert {:error, _} = Payments.send_invoice(broken, %{}, actor: admin)
    persisted = Ash.get!(Invoice, invoice.id, authorize?: false)
    assert persisted.issued_at == invoice.issued_at
    assert persisted.number == invoice.number
    assert persisted.sent_at == nil
    restored = Ash.Seed.update!(persisted, %{content: original})
    assert {:ok, sent} = Payments.send_invoice(restored, %{message: "Reminder"}, actor: admin)
    assert sent.sent_at
    assert sent.content == original

    Swoosh.TestAssertions.assert_email_sent(fn email ->
      assert email.subject =~ "A reminder about invoice"
      assert email.text_body =~ "friendly reminder"
      assert [%{filename: filename}] = email.attachments
      assert filename == "invoice-#{invoice.number}.pdf"
    end)
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
