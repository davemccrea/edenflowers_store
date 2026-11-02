defmodule EdenflowersWeb.Admin.InvoiceLiveTest do
  use EdenflowersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
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
    assert has_element?(view, "#invoice-email-form")
    issued = Ash.get!(Invoice, saved.id, actor: admin)
    assert issued.number
    assert Decimal.equal?(issued.amount, "15.02")
  end

  test "invalid line inputs block issuance and show a useful error", %{conn: conn, admin: admin} do
    invoice = draft(admin)
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    invalid = put_in(params(), ["lines", "0", "quantity"], "0")
    view |> form("#invoice-form", invoice: invalid) |> render_change()
    view |> form("#invoice-form") |> render_submit(%{"intent" => "issue"})
    assert has_element?(view, "#invoice-error", "positive quantity")
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
    invalid = put_in(params(), ["lines", "0", "quantity"], "0")

    for _ <- 1..2 do
      view |> form("#invoice-form", invoice: invalid) |> render_submit(%{"intent" => "issue"})
      assert has_element?(view, "#invoice-error", "positive quantity")
    end

    assert {:ok, [_draft]} = Ash.read(Invoice, actor: admin)
  end

  test "email failure is visible and remains retryable on the issued invoice", %{conn: conn, admin: admin} do
    {:ok, invoice} = Payments.issue_invoice(draft(admin), actor: admin)
    original = invoice.content
    Ash.Seed.update!(invoice, %{content: %{}})
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    assert has_element?(view, "button", "Send invoice")
    view |> form("#invoice-email-form", email: %{message: "Please check"}) |> render_submit()
    assert render(view) =~ "It remains issued"
    assert has_element?(view, "#invoice-email-form")
    persisted = Ash.get!(Invoice, invoice.id, actor: admin)
    assert persisted.issued_at
    assert persisted.sent_at == nil
    Ash.Seed.update!(persisted, %{content: original})
    {:ok, view, _} = live(conn, ~p"/admin/invoices/#{invoice.id}")
    view |> form("#invoice-email-form", email: %{message: "Please check"}) |> render_submit()
    assert Ash.get!(Invoice, invoice.id, actor: admin).sent_at
    assert render(view) =~ "Invoice emailed"
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
    view |> element("button", "Add line") |> render_click()
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
    refute has_element?(view, "#invoice-email-form")
    assert Ash.get!(Invoice, invoice.id, actor: admin, load: :status).status == :paid
  end
end
