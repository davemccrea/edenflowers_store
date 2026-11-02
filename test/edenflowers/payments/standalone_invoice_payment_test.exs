defmodule Edenflowers.Payments.StandaloneInvoicePaymentTest do
  use Edenflowers.DataCase, async: false
  import Generator

  alias Edenflowers.Payments
  alias Edenflowers.Payments.Invoice

  setup do
    admin = generate(admin_user())

    {:ok, draft} =
      Payments.create_invoice(
        %{
          buyer_name: "Wedding buyer",
          buyer_email: "buyer@example.com",
          buyer_address: "Street 1",
          lines: [%{description: "Booking flowers", quantity: "1", unit_price: "100", vat_rate: "25.5"}]
        },
        actor: admin
      )

    {:ok, invoice} = Payments.issue_invoice(draft, actor: admin)
    %{admin: admin, draft: draft, invoice: invoice}
  end

  test "receipts and dated reversals settle only the invoice and send no email", ctx do
    order = placed_order()
    booking = generate(course_registration())

    {:ok, partial} =
      Payments.record_invoice_payment(ctx.invoice, "40", %{paid_at: ~U[2026-09-01 08:00:00Z]}, actor: ctx.admin)

    assert Decimal.equal?(partial.amount_paid, "40")
    assert Decimal.equal?(partial.amount_unpaid, "60")
    assert partial.status == :open
    [receipt] = partial.payments
    assert receipt.order_id == nil
    assert receipt.course_registration_id == nil
    assert receipt.paid_at == ~U[2026-09-01 08:00:00Z]
    assert receipt.method == :zervant
    {:ok, paid} = Payments.record_invoice_payment(partial, "60", actor: ctx.admin)
    assert paid.status == :paid

    {:ok, reopened} =
      Payments.undo_invoice_payment(paid, receipt.id, %{paid_at: ~U[2026-10-01 08:00:00Z]}, actor: ctx.admin)

    assert Decimal.equal?(reopened.amount_paid, "60")
    assert reopened.status == :open
    reversal = Enum.find(reopened.payments, & &1.reverses_payment_id)
    assert reversal.reverses_payment_id == receipt.id
    assert reversal.paid_at == ~U[2026-10-01 08:00:00Z]
    assert Decimal.equal?(reversal.amount, "-40")
    assert {:error, _} = Payments.undo_invoice_payment(reopened, receipt.id, actor: ctx.admin)
    assert {:error, _} = Payments.undo_invoice_payment(reopened, reversal.id, actor: ctx.admin)
    assert Decimal.equal?(Ash.load!(order, :amount_paid, authorize?: false).amount_paid, "0")
    assert Decimal.equal?(Ash.load!(booking, :amount_paid, authorize?: false).amount_paid, "0")
    Swoosh.TestAssertions.assert_no_email_sent()
  end

  test "admins alone record and reverse, and cannot reverse another invoice's receipt", ctx do
    assert {:error, _} = Payments.record_invoice_payment(ctx.invoice, "10", actor: nil)
    {:ok, paid} = Payments.record_invoice_payment(ctx.invoice, "10", actor: ctx.admin)
    [receipt] = paid.payments
    assert {:error, _} = Payments.undo_invoice_payment(paid, receipt.id, actor: nil)
    {:ok, other} = Payments.create_invoice(%{}, actor: ctx.admin)
    assert {:error, _} = Payments.undo_invoice_payment(other, receipt.id, actor: ctx.admin)
    assert Decimal.equal?(Ash.load!(paid, :amount_paid, authorize?: false).amount_paid, "10")
  end

  test "drafts, credited invoices and stale pre-credit values cannot receive money", ctx do
    {:ok, draft} = Payments.create_invoice(%{}, actor: ctx.admin)
    assert {:error, _} = Payments.record_invoice_payment(draft, "10", actor: ctx.admin)
    {:ok, _credit} = Payments.cancel_invoice(%{invoice_id: ctx.invoice.id}, actor: ctx.admin)
    assert {:error, _} = Payments.record_invoice_payment(ctx.invoice, "10", actor: ctx.admin)
    assert Ash.load!(ctx.invoice, :status, authorize?: false).status == :cancelled
    assert Enum.empty?(Ash.load!(ctx.invoice, :payments, authorize?: false).payments)
  end

  test "a payment committed first prevents a credit from stale invoice state", ctx do
    assert {:ok, _} = Payments.record_invoice_payment(ctx.invoice, "0.01", actor: ctx.admin)
    assert {:error, _} = Payments.cancel_invoice(%{invoice_id: ctx.invoice.id}, actor: ctx.admin)
    assert Ash.load!(ctx.invoice, :status, authorize?: false).status == :open
  end

  test "database enforces exactly one of three owners and preserves purchase payments", ctx do
    order = placed_order()
    booking = generate(course_registration())
    assert generate(payment(order_id: order.id)).order_id == order.id
    assert generate(payment(course_registration_id: booking.id)).course_registration_id == booking.id

    for attrs <- [
          %{},
          %{order_id: order.id, invoice_id: ctx.invoice.id},
          %{course_registration_id: booking.id, invoice_id: ctx.invoice.id},
          %{order_id: order.id, course_registration_id: booking.id}
        ] do
      assert {:error, %Postgrex.Error{postgres: postgres}} =
               Edenflowers.Repo.query(
                 "INSERT INTO payments (id, amount, method, goodwill, paid_at, inserted_at, updated_at, order_id, course_registration_id, invoice_id) VALUES ($1, 1, 'zervant', false, now(), now(), now(), $2, $3, $4)",
                 Enum.map(
                   [Ecto.UUID.generate(), attrs[:order_id], attrs[:course_registration_id], attrs[:invoice_id]],
                   fn id -> if id, do: Ecto.UUID.dump!(id) end
                 ),
                 mode: :savepoint
               )

      assert postgres.constraint == "payments_one_parent"
    end

    assert Ash.get!(Invoice, ctx.invoice.id, authorize?: false).id == ctx.invoice.id
  end
end
