defmodule EdenflowersWeb.Admin.InvoiceLiveTest do
  use EdenflowersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  alias Edenflowers.Payments
  alias Edenflowers.Payments.Invoice

  setup :log_in_admin

  defp params do
    %{
      "buyer_name" => "Wedding Buyer",
      "buyer_email" => "buyer@example.com",
      "buyer_address" => "Street 1, Vaasa",
      "business_customer" => "false",
      "locale" => "en-GB",
      "invoice_date" => Date.to_iso8601(Edenflowers.ShopTime.today()),
      "due_date" => Date.to_iso8601(Date.add(Edenflowers.ShopTime.today(), 14)),
      "lines" => %{
        "0" => %{
          "description" => "Wedding booking flowers",
          "quantity" => "1.5",
          "unit_price" => "10.01",
          "vat_rate" => "25.5"
        }
      }
    }
  end

  defp draft(admin) do
    attrs = params() |> Map.put("lines", Map.values(params()["lines"]))
    {:ok, draft} = Payments.create_invoice(attrs, actor: admin)
    draft
  end

  test "standalone draft previews totals, saves, and issues without a purchase", %{conn: conn, admin: admin} do
    {:ok, view, _} = live(conn, ~p"/admin/invoices/new")
    view |> form("#invoice-form", invoice: params()) |> render_change()
    assert has_element?(view, "#invoice-totals", "15,02")
    view |> form("#invoice-form", invoice: params()) |> render_submit()
    {path, _} = assert_redirect(view)
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#invoice-form")
    assert {:ok, [saved]} = Ash.read(Invoice, actor: admin)
    assert saved.number == nil
    view |> form("#invoice-form") |> render_submit(%{"intent" => "issue"})
    {path, _} = assert_redirect(view)
    {:ok, view, _} = live(conn, path)
    refute has_element?(view, "#invoice-form")
    assert has_element?(view, "a[href$='/pdf']", "Download PDF")
    assert has_element?(view, "button[phx-click=open_email][phx-value-kind=invoice]")
    issued = Ash.get!(Invoice, saved.id, actor: admin)
    assert issued.number
    assert Decimal.equal?(issued.amount, "15.02")
  end

  test "saved drafts and issued invoices show lifecycle history", %{conn: conn, admin: admin} do
    invoice = draft(admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    assert has_element?(view, "#invoice-log", "Draft created")
    refute has_element?(view, "#invoice-log", "Invoice issued")
    {:ok, _} = Payments.issue_invoice(invoice, actor: admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    assert has_element?(view, "#invoice-log", "Invoice issued")
    assert has_element?(view, "#invoice-log time[datetime]")
  end

  test "history preserves every invoice email, reminder and message", %{conn: conn, admin: admin} do
    {:ok, invoice} = Payments.issue_invoice(draft(admin), actor: admin)
    {:ok, _} = Payments.send_invoice(invoice, %{message: "First email"}, actor: admin)
    {:ok, _} = Payments.send_invoice(invoice, %{message: "A second copy"}, actor: admin)
    # Moving the business date makes the next send a reminder without changing earlier send metadata.
    invoice = Ash.Seed.update!(invoice, %{invoice_date: ~D[2025-01-01], due_date: ~D[2025-01-15]})
    {:ok, _} = Payments.send_invoice(invoice, %{message: "Reminder message"}, actor: admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    assert has_element?(view, "#invoice-log", "First email")
    assert has_element?(view, "#invoice-log", "A second copy")
    assert has_element?(view, "#invoice-log", "Reminder message")
    assert has_element?(view, "#invoice-log", "Payment reminder emailed")
    assert has_element?(view, "#invoice-log details summary")
    assert has_element?(view, "#invoice-log", "buyer@example.com")
    assert length(Ash.load!(invoice, :paper_trail_versions, actor: admin).paper_trail_versions) == 3
  end

  test "payment, reversal and credit events refresh the same history", %{conn: conn, admin: admin} do
    {:ok, invoice} = Payments.issue_invoice(draft(admin), actor: admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    view |> form("#invoice-payment-form", payment: %{amount: "5", paid_on: "2026-11-02"}) |> render_submit()
    assert has_element?(view, "#invoice-log", "Paid")
    assert has_element?(view, "#invoice-log", "Bank transfer")
    view |> element("button", "Reverse payment") |> render_click()
    assert has_element?(view, "#invoice-log", "Undid")
    view |> form("#invoice-credit-form", credit: %{reason: "Replace incorrect details"}) |> render_submit()
    note = Ash.load!(invoice, :credit_note, actor: admin).credit_note
    assert has_element?(view, "#invoice-log", "Credit note #{note.number} issued")
    assert has_element?(view, "#invoice-log", "Replace incorrect details")

    for message <- ["First credit email", "Second credit email"] do
      view |> element("button[phx-click=open_email][phx-value-kind=credit_note]") |> render_click()
      view |> form("#email-form", email: %{message: message}) |> render_submit()
    end

    assert has_element?(view, "#invoice-log", "First credit email")
    assert has_element?(view, "#invoice-log", "Second credit email")
    assert length(Ash.load!(note, :paper_trail_versions, actor: admin).paper_trail_versions) == 2
  end

  test "optional invoice details reopen on an existing draft and business addresses stay distinct", %{
    conn: conn,
    admin: admin
  } do
    {:ok, invoice} =
      Payments.update_invoice_draft(
        draft(admin),
        %{customer_reference: "Wedding PO", supply_date: ~D[2026-12-01], supply_description: "Flowers supplied"},
        actor: admin
      )

    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    assert has_element?(view, "#invoice-additional-details[open]")
    assert has_element?(view, "input[name='invoice[customer_reference]'][value='Wedding PO']")
    view |> form("#invoice-form", invoice: %{business_customer: "true"}) |> render_change()
    refute has_element?(view, "textarea[name='invoice[buyer_address]']")
    assert has_element?(view, "input[type=hidden][name='invoice[buyer_address]'][value='Street 1, Vaasa']")
    assert has_element?(view, "textarea[name='invoice[billing_address]']")
    view |> form("#invoice-form", invoice: %{business_customer: "false"}) |> render_change()
    assert has_element?(view, "textarea[name='invoice[buyer_address]']", "Street 1, Vaasa")
  end

  test "part payment is deducted from the original total and leaves a clear balance", %{conn: conn, admin: admin} do
    {:ok, invoice} = Payments.issue_invoice(draft(admin), actor: admin)
    {:ok, _} = Payments.record_invoice_payment(invoice, "5", %{}, actor: admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    assert has_element?(view, "#invoice-totals", "15,02")
    assert has_element?(view, "#invoice-totals", "−5,00")
    assert has_element?(view, "#invoice-totals", "10,02")
    assert has_element?(view, "#invoice-totals a[href='#invoice-payment-form']", "Record payment")
    refute has_element?(view, "#invoice-corrections")
  end

  test "full credit is an intentional disclosure while ordinary invoice actions stay available", %{
    conn: conn,
    admin: admin
  } do
    {:ok, invoice} = Payments.issue_invoice(draft(admin), actor: admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    assert has_element?(view, "#invoice-corrections summary", "Correct this invoice")
    refute has_element?(view, "#invoice-corrections[open]")
    assert has_element?(view, "button[phx-click=open_email][phx-value-kind=invoice]", "Send invoice")
    assert has_element?(view, "#invoice-payment-form")
    assert has_element?(view, "#invoice-credit-form button[data-confirm]")
  end

  test "invalid line inputs block issuance and show a useful error", %{conn: conn, admin: admin} do
    invoice = draft(admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    invalid = put_in(params(), ["lines", "0", "quantity"], "0")
    view |> form("#invoice-form", invoice: invalid) |> render_change()
    view |> form("#invoice-form") |> render_submit(%{"intent" => "issue"})
    assert has_element?(view, "#line-0-quantity[aria-invalid=true]")
    assert has_element?(view, "#line-0-quantity-error", "must be greater than 0")
    assert Ash.get!(Invoice, invoice.id, actor: admin).number == nil
  end

  test "payments, reversals and unpaid credits update history and the appropriate actions", %{conn: conn, admin: admin} do
    {:ok, invoice} = Payments.issue_invoice(draft(admin), actor: admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    view |> form("#invoice-payment-form", payment: %{amount: "5", paid_on: "2026-11-02"}) |> render_submit()
    assert has_element?(view, "#accountant-correction", "contact the accountant")
    refute has_element?(view, "#invoice-credit-form")
    view |> element("button", "Reverse payment") |> render_click()
    assert has_element?(view, "#invoice-credit-form")
    assert render(view) =~ "Reversal"
    view |> form("#invoice-credit-form", credit: %{reason: "Replaced invoice"}) |> render_submit()
    assert render(view) =~ "Credited"
    refute has_element?(view, "#invoice-payment-form")
    assert has_element?(view, "a[href^='/admin/credit-notes/']")
    assert Ash.load!(invoice, :status).status == :cancelled
  end

  test "bank transfers accept decimal commas", %{conn: conn, admin: admin} do
    {:ok, invoice} = Payments.issue_invoice(draft(admin), actor: admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")

    view
    |> form("#invoice-payment-form",
      payment: %{amount: "10,00", paid_on: Date.to_iso8601(Edenflowers.ShopTime.today())}
    )
    |> render_submit()

    assert has_element?(view, "#accountant-correction")
    invoice = Ash.get!(Invoice, invoice.id, actor: admin, load: [:amount_paid, :amount_unpaid, :payments])
    assert Decimal.equal?(invoice.amount_paid, "10.00")
    assert Decimal.equal?(invoice.amount_unpaid, "5.02")
    assert [%{amount: amount}] = invoice.payments
    assert Decimal.equal?(amount, "10.00")
  end

  test "validation stays quiet until a field is used and updates as it is corrected", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/admin/invoices/new")
    refute has_element?(view, "[aria-invalid=true]")
    assert has_element?(view, "#invoice-totals [role=status]", "Complete the items to see the total.")

    input =
      params()
      |> put_in(["lines", "0", "quantity"], "0")
      |> put_in(["lines", "0", "unit_price"], "bad")
      |> put_in(["lines", "0", "_unused_unit_price"], "")
      |> Map.put("buyer_email", "invalid")
      |> Map.put("_unused_buyer_email", "")

    render_change(view, "validate", %{"invoice" => input})
    assert has_element?(view, "#line-0-quantity[aria-invalid=true][aria-describedby=line-0-quantity-error]")
    refute has_element?(view, "#line-0-price[aria-invalid=true]")
    refute has_element?(view, "input[name='invoice[buyer_email]'][aria-invalid=true]")

    input = input |> Map.delete("_unused_buyer_email") |> put_in(["lines", "0", "quantity"], "2")
    render_change(view, "validate", %{"invoice" => input})
    refute has_element?(view, "#line-0-quantity[aria-invalid=true]")
    assert has_element?(view, "input[name='invoice[buyer_email]'][aria-invalid=true]")
    view |> form("#invoice-form", invoice: params()) |> render_change()
    refute has_element?(view, "[aria-invalid=true]")
  end

  test "issuance reveals required buyer and date errors and corrections clear them", %{conn: conn, admin: admin} do
    {:ok, view, _} = live(conn, ~p"/admin/invoices/new")
    input = params() |> Map.merge(%{"buyer_name" => "", "buyer_address" => "", "due_date" => "2020-01-01"})
    view |> form("#invoice-form", invoice: input) |> render_submit(%{"intent" => "issue"})
    assert has_element?(view, "input[name='invoice[buyer_name]'][aria-invalid=true]")
    assert has_element?(view, "textarea[name='invoice[buyer_address]'][aria-invalid=true]")
    assert has_element?(view, "input[name='invoice[due_date]'][aria-invalid=true]")
    assert {:ok, [%{number: nil}]} = Ash.read(Invoice, actor: admin)
    view |> form("#invoice-form", invoice: params()) |> render_change()
    refute has_element?(view, "[aria-invalid=true]")
    refute has_element?(view, "#invoice-error")
    view |> form("#invoice-form") |> render_submit(%{"intent" => "issue"})
    assert_redirect(view)
    assert {:ok, [%{number: number}]} = Ash.read(Invoice, actor: admin)
    assert number
  end

  test "business issuance marks company fields and stops requiring the personal address", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/admin/invoices/new")

    input =
      params()
      |> Map.merge(%{
        "business_customer" => "true",
        "buyer_address" => "",
        "company_name" => "",
        "business_id" => "",
        "billing_address" => ""
      })

    render_change(view, "validate", %{"invoice" => input})
    view |> form("#invoice-form", invoice: input) |> render_submit(%{"intent" => "issue"})

    for field <- ~w(company_name business_id billing_address) do
      assert has_element?(view, "[name='invoice[#{field}]'][aria-invalid=true]")
    end

    refute has_element?(view, "[name='invoice[buyer_address]'][aria-invalid=true]")
    input = Map.put(input, "business_customer", "false")
    render_change(view, "validate", %{"invoice" => input})
    refute has_element?(view, "[name='invoice[company_name]']")
    assert has_element?(view, "[name='invoice[buyer_address]'][aria-invalid=true]")
  end

  test "failed credit submission preserves the reason", %{conn: conn, admin: admin} do
    {:ok, invoice} = Payments.issue_invoice(draft(admin), actor: admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    # Another session records money after this page was loaded.
    {:ok, _} = Payments.record_invoice_payment(invoice, "1", %{}, actor: admin)
    view |> form("#invoice-credit-form", credit: %{reason: "Customer requested a correction"}) |> render_submit()
    assert has_element?(view, "#invoice-error")
    assert has_element?(view, "#invoice-credit-form textarea", "Customer requested a correction")
    assert Ash.load!(invoice, :credit_note, actor: admin).credit_note == nil
  end

  test "incomplete drafts remain saveable", %{conn: conn, admin: admin} do
    {:ok, view, _} = live(conn, ~p"/admin/invoices/new")
    view |> form("#invoice-form") |> render_submit()
    assert_redirect(view)
    assert {:ok, [%{number: nil, buyer_name: nil}]} = Ash.read(Invoice, actor: admin)
  end

  test "new lines are untouched and errors stay with their line after removal", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/admin/invoices/new")
    view |> element("button", "Add item") |> render_click()
    refute has_element?(view, "[aria-invalid=true]")

    input =
      params()
      |> put_in(["lines", "1"], %{
        "description" => "Second",
        "quantity" => "0",
        "unit_price" => "5",
        "vat_rate" => "25.5"
      })

    render_change(view, "validate", %{"invoice" => input})
    assert has_element?(view, "#line-1-quantity[aria-invalid=true]")
    view |> element("#invoice-line-0 button") |> render_click()
    assert has_element?(view, "#line-0-description[value=Second]")
    assert has_element?(view, "#line-0-quantity[aria-invalid=true]")
    refute has_element?(view, "#invoice-line-1")
  end

  test "invalid bank transfers mark fields, retain input, and do not create payments", %{conn: conn, admin: admin} do
    {:ok, invoice} = Payments.issue_invoice(draft(admin), actor: admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    view |> form("#invoice-payment-form", payment: %{amount: "-2,00", paid_on: ""}) |> render_submit()
    assert has_element?(view, "input[name='payment[amount]'][value='-2,00'][aria-invalid=true]")
    assert has_element?(view, "input[name='payment[paid_on]'][aria-invalid=true]")
    assert Ash.load!(invoice, :payments).payments == []
    view |> form("#invoice-payment-form", payment: %{amount: "5,00", paid_on: "2026-11-02"}) |> render_change()
    refute has_element?(view, "[aria-invalid=true]")
    refute has_element?(view, "#invoice-error")
    view |> form("#invoice-payment-form") |> render_submit()
    assert has_element?(view, "#accountant-correction")
  end

  test "register links to drafts and issued invoices", %{conn: conn, admin: admin} do
    invoice = draft(admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices")
    assert has_element?(view, "a[href='/admin/invoices/#{invoice.id}']", "Draft")

    assert render(view) =~ "Wedding Buyer"
  end

  test "drafts have no downloadable document", %{conn: conn, admin: admin} do
    invoice = draft(admin)
    conn = get(conn, ~p"/admin/invoices/#{invoice.id}/pdf")
    assert conn.status == 404
  end

  test "failed new issuance keeps one draft for correction", %{conn: conn, admin: admin} do
    {:ok, view, _} = live(conn, ~p"/admin/invoices/new")
    invalid = put_in(params(), ["lines", "0", "quantity"], "")

    for _ <- 1..2 do
      view |> form("#invoice-form", invoice: invalid) |> render_submit(%{"intent" => "issue"})
      assert has_element?(view, "#line-0-quantity[aria-invalid=true]")
      assert has_element?(view, "#line-0-quantity-error")
    end

    assert {:ok, [_draft]} = Ash.read(Invoice, actor: admin)
  end

  test "email failure is visible and remains retryable on the issued invoice", %{conn: conn, admin: admin} do
    {:ok, invoice} = Payments.issue_invoice(draft(admin), actor: admin)
    original = invoice.content
    Ash.Seed.update!(invoice, %{content: %{}})
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    assert has_element?(view, "button", "Send invoice")
    view |> element("button[phx-click=open_email][phx-value-kind=invoice]") |> render_click()
    view |> form("#email-form", email: %{message: "Please check"}) |> render_submit()
    assert render(view) =~ "It remains issued"
    assert has_element?(view, "#email-form")
    assert has_element?(view, "#email-form textarea", "Please check")
    refute has_element?(view, "#invoice-log", "Invoice emailed")
    persisted = Ash.get!(Invoice, invoice.id, actor: admin)
    assert persisted.issued_at
    assert persisted.sent_at == nil
    Ash.Seed.update!(persisted, %{content: original})
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    view |> element("button[phx-click=open_email][phx-value-kind=invoice]") |> render_click()
    view |> form("#email-form", email: %{message: "Please check"}) |> render_submit()
    assert Ash.get!(Invoice, invoice.id, actor: admin).sent_at
    assert render(view) =~ "Invoice emailed"
  end

  test "invoice emails require the shared preview drawer and cancel sends nothing", %{conn: conn, admin: admin} do
    {:ok, invoice} = Payments.issue_invoice(draft(admin), actor: admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    refute has_element?(view, "#email-form")
    render_hook(view, "send_email", %{"email" => %{"message" => "Bypass"}})
    assert Ash.get!(Invoice, invoice.id, actor: admin).sent_at == nil
    assert_no_email_sent()

    view |> element("button[phx-click=open_email][phx-value-kind=invoice]") |> render_click()
    assert_push_event(view, "js-exec", %{to: "#email-drawer", attr: "phx-show"})
    assert has_element?(view, "#email-form")
    assert has_element?(view, "#email-drawer [aria-label='Email preview']", "Invoice #{invoice.number}")
    assert has_element?(view, "#email-drawer", "buyer@example.com")
    assert has_element?(view, "#email-drawer", "#{invoice.number}.pdf")
    view |> form("#email-form", email: %{message: "Please read this before paying."}) |> render_change()
    assert has_element?(view, "#email-drawer [aria-label='Email preview']", "Please read this before paying.")
    render_hook(view, "close_email", %{})
    refute has_element?(view, "#email-form")
    render_hook(view, "send_email", %{"email" => %{"message" => "After closing"}})
    assert Ash.get!(Invoice, invoice.id, actor: admin).sent_at == nil
    assert_no_email_sent()
  end

  test "credit note emails preview the attachment and custom message before sending", %{conn: conn, admin: admin} do
    {:ok, invoice} = Payments.issue_invoice(draft(admin), actor: admin)
    {:ok, note} = Payments.cancel_invoice(%{invoice_id: invoice.id}, actor: admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    refute has_element?(view, "#email-form")
    view |> element("button[phx-click=open_email][phx-value-kind=credit_note]") |> render_click()
    assert_push_event(view, "js-exec", %{to: "#email-drawer", attr: "phx-show"})
    assert has_element?(view, "#email-drawer [aria-label='Email preview']", "#{note.number}.pdf")
    view |> form("#email-form", email: %{message: "Your replacement will follow."}) |> render_change()
    assert has_element?(view, "#email-drawer [aria-label='Email preview']", "Your replacement will follow.")
    assert_no_email_sent()
    view |> form("#email-form") |> render_submit()
    assert render(view) =~ "Credit note emailed."
    assert_push_event(view, "js-exec", %{to: "#email-drawer", attr: "phx-hide"})
    refute has_element?(view, "#email-form")
    assert Payments.get_credit_note!(note.id, actor: admin).sent_at
    assert_email_sent(fn email -> assert email.text_body =~ "Your replacement will follow." end)
  end

  test "creating a credit note cannot bypass the email preview", %{conn: conn, admin: admin} do
    {:ok, invoice} = Payments.issue_invoice(draft(admin), actor: admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")

    render_hook(view, "credit", %{
      "credit" => %{"reason" => "Correction", "email_customer?" => "true", "message" => "Do not send yet"}
    })

    assert has_element?(view, "button[phx-click=open_email][phx-value-kind=credit_note]")
    credit_note = Ash.load!(invoice, :credit_note, actor: admin).credit_note
    assert credit_note.sent_at == nil
    assert_no_email_sent()
  end

  test "previous invoice customers are deduplicated and selection copies their latest details only", %{
    conn: conn,
    admin: admin
  } do
    {:ok, old} = Payments.issue_invoice(draft(admin), actor: admin)
    Ash.Seed.update!(old, %{sent_at: ~U[2026-10-01 12:00:00Z]})

    {:ok, updated} =
      Payments.update_invoice_draft(
        draft(admin),
        %{
          buyer_name: "Updated Customer",
          buyer_email: "BUYER@example.com",
          buyer_address: "Updated address",
          locale: "fi"
        },
        actor: admin
      )

    {:ok, latest} = Payments.issue_invoice(updated, actor: admin)
    latest = Ash.Seed.update!(latest, %{sent_at: ~U[2026-10-02 12:00:00Z]})
    # Drafts and issued-but-unsent documents are not previous emailed customers.
    draft(admin)
    {:ok, _unsent} = Payments.issue_invoice(draft(admin), actor: admin)
    assert [%{id: id}] = Payments.search_invoice_customers!("BUYER@EXAMPLE", actor: admin)
    assert id == latest.id

    {:ok, view, _} = live(conn, ~p"/admin/invoices/new")
    view |> form("#invoice-form", invoice: params()) |> render_change()
    view |> element("#invoice_previous_invoice_id_text_input") |> render_change(%{"text" => "buyer@example"})
    render_hook(view, "live_select_change", %{"id" => "customer-select", "text" => "buyer@example"})
    render(view)
    assert has_element?(view, "#customer-select ul", "Updated Customer")
    view |> element("#customer-select") |> render_hook("option_click", %{"idx" => "0"})
    assert_push_event(view, "select", %{id: "customer-select", selection: [%{value: ^id}]})
    view |> form("#invoice-form", invoice: %{previous_invoice_id: id}) |> render_change()
    assert has_element?(view, "input[name='invoice[buyer_name]'][value='Updated Customer']")
    assert has_element?(view, "textarea[name='invoice[buyer_address]']", "Updated address")
    assert has_element?(view, "select[name='invoice[locale]'] option[selected][value=fi]")
    assert has_element?(view, "#line-0-description[value='Wedding booking flowers']")
    assert has_element?(view, "input[name='invoice[due_date]'][value='#{params()["due_date"]}']")

    view |> form("#invoice-form", invoice: %{buyer_name: "Manually edited"}) |> render_change()
    assert has_element?(view, "input[name='invoice[buyer_name]'][value='Manually edited']")
    view |> element("#customer-select button[phx-click=clear]") |> render_click()
    view |> form("#invoice-form", invoice: %{previous_invoice_id: ""}) |> render_change()
    assert has_element?(view, "input[name='invoice[buyer_name]'][value='Manually edited']")
    assert Ash.get!(Invoice, latest.id, actor: admin).buyer_name == "Updated Customer"
  end

  test "business customer selection fills company fields without copying invoice-specific references", %{
    conn: conn,
    admin: admin
  } do
    {:ok, previous} =
      Payments.update_invoice_draft(
        draft(admin),
        %{
          business_customer: true,
          company_name: "Example Company",
          business_id: "2944459-6",
          billing_address: "Company address",
          customer_reference: "Old PO"
        },
        actor: admin
      )

    {:ok, previous} = Payments.issue_invoice(previous, actor: admin)
    previous = Ash.Seed.update!(previous, %{sent_at: ~U[2026-10-02 12:00:00Z]})
    {:ok, view, _} = live(conn, ~p"/admin/invoices/new")
    render_change(view, "validate", %{"invoice" => Map.put(params(), "previous_invoice_id", previous.id)})
    assert has_element?(view, "input[name='invoice[business_customer]'][type=checkbox][checked]")
    assert has_element?(view, "input[name='invoice[company_name]'][value='Example Company']")
    assert has_element?(view, "input[name='invoice[business_id]'][value='2944459-6']")
    assert has_element?(view, "textarea[name='invoice[billing_address]']", "Company address")
    refute has_element?(view, "input[name='invoice[customer_reference]'][value='Old PO']")
  end

  test "unsent invoices cannot be selected to prefill and no-match search is explained", %{conn: conn, admin: admin} do
    unsent = draft(admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices/new")

    render_change(view, "validate", %{
      "invoice" => Map.put(params(), "previous_invoice_id", unsent.id) |> Map.put("buyer_name", "Keep this")
    })

    assert has_element?(view, "input[name='invoice[buyer_name]'][value='Keep this']")
    render_hook(view, "live_select_change", %{"id" => "customer-select", "text" => "No such customer"})
    assert has_element?(view, "#customer-results", "No customers found.")
    assert {:error, _} = Payments.search_invoice_customers("buyer", actor: nil)
  end

  test "VAT uses the shared rate choices while a draft retains a historical percentage", %{conn: conn, admin: admin} do
    Generator.generate(Generator.tax_rate(name: "Standard VAT", percentage: "0.255"))
    Generator.generate(Generator.tax_rate(name: "Reduced VAT", percentage: "0.135"))
    {:ok, view, _} = live(conn, ~p"/admin/invoices/new")
    assert has_element?(view, "select#line-0-vat option[value='25.5']", "Standard VAT")
    assert has_element?(view, "select#line-0-vat option[value='13.5']", "Reduced VAT")
    assert has_element?(view, "select#line-0-vat option[value='25.5'][selected]")

    {:ok, draft} =
      Payments.update_invoice_draft(
        draft(admin),
        %{lines: [%{description: "Historical", quantity: "1", unit_price: "10", vat_rate: "14"}]},
        actor: admin
      )

    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{draft.id}")
    assert has_element?(view, "select#line-0-vat option[value='14'][selected]", "14%")

    assert has_element?(view, "select#line-0-vat option[value='25.5']", "Standard VAT")
  end

  test "non-admins cannot manage invoices or download documents", %{conn: conn, admin: admin} do
    {:ok, invoice} = Payments.issue_invoice(draft(admin), actor: admin)
    anonymous = build_conn()
    assert {:error, {:redirect, _}} = live(anonymous, ~p"/admin/invoices")
    assert get(anonymous, ~p"/admin/invoices/#{invoice.id}/pdf").status == 404
    user = Generator.generate(Generator.admin_user(admin: false)) |> Generator.with_token()
    customer = log_in(recycle(conn), user)
    assert {:error, {:redirect, _}} = live(customer, ~p"/admin/invoices/#{invoice.id}")
    assert get(customer, ~p"/admin/invoices/#{invoice.id}/pdf").status == 404
  end

  test "billed lines can be added and removed with localized decimal inputs", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/admin/invoices/new")

    localized =
      params()
      |> put_in(["lines", "0", "unit_price"], "10,01")
      |> put_in(["lines", "0", "quantity"], "1,5")

    view |> form("#invoice-form", invoice: localized) |> render_change()
    assert has_element?(view, "#invoice-totals", "15,02")
    view |> element("button", "Add item") |> render_click()
    assert has_element?(view, "#invoice-line-1")
    view |> element("#invoice-line-1 button") |> render_click()
    refute has_element?(view, "#invoice-line-1")
    assert has_element?(view, "#invoice-totals", "15,02")
  end

  test "overdue reminder and paid states remain distinct", %{conn: conn, admin: admin} do
    invoice = draft(admin)

    {:ok, invoice} =
      Payments.update_invoice_draft(invoice, %{invoice_date: ~D[2025-01-01], due_date: ~D[2025-01-15]}, actor: admin)

    {:ok, invoice} = Payments.issue_invoice(invoice, actor: admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    assert has_element?(view, "button", "Send reminder")

    view
    |> form("#invoice-payment-form",
      payment: %{amount: "15.02", paid_on: Date.to_iso8601(Edenflowers.ShopTime.today())}
    )
    |> render_submit()

    assert has_element?(view, "#accountant-correction")
    refute has_element?(view, "#invoice-payment-form")
    refute has_element?(view, "#email-form")
    assert Ash.get!(Invoice, invoice.id, actor: admin, load: :status).status == :paid
  end
end
