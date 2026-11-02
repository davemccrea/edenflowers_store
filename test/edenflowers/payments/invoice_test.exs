defmodule Edenflowers.Payments.InvoiceTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Courses
  alias Edenflowers.Email
  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias Edenflowers.Payments
  alias Edenflowers.Payments.Changes.SendInvoice
  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.ReferenceNumber
  alias Edenflowers.Payments.Workers.SendCancelledEmail
  alias Edenflowers.ShopTime

  @company %{
    business_customer: true,
    company_name: "Kukka Oy",
    business_id: "2944459-6",
    billing_address: "Kyrkvägen 5\n68600 Jakobstad"
  }

  setup do
    %{admin: generate(admin_user())}
  end

  defp invoice(purchase_attrs, ctx, attrs \\ %{}) do
    Payments.create_invoice(Map.merge(purchase_attrs, attrs), actor: ctx.admin)
  end

  defp error_message({:error, error}), do: Exception.message(error)

  describe "creating one" do
    test "needs invoice terms", ctx do
      order = placed_order(payment_terms: :payment_link)

      assert error_message(invoice(%{order_id: order.id}, ctx)) =~ "Only a purchase on invoice terms"
    end

    test "needs the customer's email", ctx do
      order = placed_order(payment_terms: :invoice, customer_email: nil)

      assert error_message(invoice(%{order_id: order.id}, ctx)) =~ "name and email"
    end

    test "for a business customer needs the company details, which can be added after delivery", ctx do
      order =
        placed_order(
          payment_terms: :invoice,
          fulfillment_status: :fulfilled,
          business_customer: true,
          company_name: "Kukka Oy"
        )

      assert error_message(invoice(%{order_id: order.id}, ctx)) =~ "company name, Y-tunnus and billing address"
      assert Ash.load!(order, :missing_business_details).missing_business_details == [:business_id, :billing_address]

      {:ok, order} = Orders.update_order_business_details(order, @company, actor: ctx.admin)

      assert {:ok, invoice} = invoice(%{order_id: order.id}, ctx)
      assert invoice.company_name == "Kukka Oy"
    end

    test "is open to a cancelled booking, to bill what Jennie kept", ctx do
      registration =
        generate(course_registration(status: :cancelled, payment_terms: :invoice, kept_amount: Decimal.new("40.00")))

      {:ok, registration} = Courses.update_registration_business_details(registration, @company, actor: ctx.admin)

      assert {:ok, invoice} = invoice(%{course_registration_id: registration.id}, ctx)
      assert Decimal.equal?(invoice.amount, "40.00")
    end
  end

  test "numbers follow on without gaps, each with a valid viitenumero", ctx do
    order = placed_order(payment_terms: :invoice)

    {:ok, first} = invoice(%{order_id: order.id}, ctx, %{amount: "20.00"})
    {:error, _} = invoice(%{order_id: order.id}, ctx, %{amount: "10.00", locale: "de"})
    {:ok, second} = invoice(%{order_id: order.id}, ctx, %{amount: "10.00"})

    assert first.number == Invoice.first_number()
    assert second.number == first.number + 1
    assert ReferenceNumber.valid?(second.reference_number)
    assert String.starts_with?(second.reference_number, Integer.to_string(second.number))
  end

  test "defaults to the Balance not yet invoiced, due in 14 days, in the purchase's language", ctx do
    order = placed_order(payment_terms: :invoice, paid: "8.50", locale: "fi")

    {:ok, booking_fee} =
      invoice(%{order_id: order.id}, ctx, %{amount: "30.00", due_date: Date.add(ShopTime.today(), 30)})

    {:ok, rest} = invoice(%{order_id: order.id}, ctx)

    assert booking_fee.due_date == Date.add(ShopTime.today(), 30)
    assert Decimal.equal?(rest.amount, "50.00")
    assert rest.invoice_date == ShopTime.today()
    assert rest.due_date == Date.add(ShopTime.today(), 14)
    assert rest.locale == "fi"

    assert error_message(invoice(%{order_id: order.id}, ctx)) =~ "nothing is left to invoice"
  end

  describe "paying one by bank transfer" do
    defp pay(purchase, amount, invoice, ctx, input \\ %{}) do
      Orders.record_payment(purchase, amount, :zervant, Map.put(input, :invoice_id, invoice.id), actor: ctx.admin)
    end

    defp reload(invoice), do: Ash.load!(invoice, [:status, :paid?, :amount_paid], authorize?: false)

    defp uninvoiced(order), do: Ash.load!(order, :uninvoiced_balance, authorize?: false).uninvoiced_balance

    test "is paid once its Payments cover it, and open again once one is undone", ctx do
      order = placed_order(payment_terms: :invoice, payment_intent_id: nil)
      {:ok, invoice} = invoice(%{order_id: order.id}, ctx, %{amount: "50.00"})

      {:ok, order} = pay(order, "20.00", invoice, ctx)
      assert reload(invoice).status == :open

      {:ok, order} = pay(order, "30.00", invoice, ctx)
      assert reload(invoice).paid?

      thirty = Enum.find(Ash.load!(order, :payments, authorize?: false).payments, &Decimal.equal?(&1.amount, "30.00"))
      {:ok, _order} = Orders.undo_payment(order, thirty.id, actor: ctx.admin)

      invoice = reload(invoice)
      assert invoice.status == :open
      assert Decimal.equal?(invoice.amount_paid, "20.00")
    end

    test "leaves what is still to invoice where it was", ctx do
      order = placed_order(payment_terms: :invoice, payment_intent_id: nil)
      {:ok, booking_fee} = invoice(%{order_id: order.id}, ctx, %{amount: "30.00"})
      assert Decimal.equal?(uninvoiced(order), "58.50")

      {:ok, order} = pay(order, "10.00", booking_fee, ctx)
      assert Decimal.equal?(uninvoiced(order), "58.50")

      {:ok, order} = pay(order, "20.00", booking_fee, ctx)
      assert Decimal.equal?(uninvoiced(order), "58.50")
    end

    test "can't pay another purchase's invoice", ctx do
      order = placed_order(payment_terms: :invoice, payment_intent_id: nil)
      other = placed_order(payment_terms: :invoice, payment_intent_id: nil)
      {:ok, others_invoice} = invoice(%{order_id: other.id}, ctx)

      assert error_message(pay(order, "10.00", others_invoice, ctx)) =~ "isn't for this purchase"
    end

    test "still emails Payment received", ctx do
      order = placed_order(payment_terms: :invoice, payment_intent_id: nil)
      {:ok, invoice} = invoice(%{order_id: order.id}, ctx)

      {:ok, order} = pay(order, "88.50", invoice, ctx, %{email_receipt?: true})

      assert order.__metadata__.receipt_emailed?

      Swoosh.TestAssertions.assert_email_sent(fn email ->
        assert email.to == [{"", "ada@example.com"}]
        assert email.text_body =~ "I've received your payment of 88,50 €."
      end)
    end
  end

  describe "emailing one" do
    test "goes out on creating when asked, in the invoice's language with its PDF", ctx do
      order = placed_order(payment_terms: :invoice, locale: "en-GB") |> Ash.Seed.update!(@company)

      {:ok, invoice} =
        invoice(%{order_id: order.id}, ctx, %{locale: "fi", email_customer?: true, message: "Kiitos paljon!"})

      assert invoice.__metadata__.emailed?
      assert invoice.sent_at

      Swoosh.TestAssertions.assert_email_sent(fn email ->
        assert email.to == [{"", "ada@example.com"}]
        assert email.text_body =~ "Kiitos paljon!"
        assert email.text_body =~ ReferenceNumber.format(invoice.reference_number)
        assert [%{filename: filename, content_type: "application/pdf"}] = email.attachments
        assert filename == "lasku-#{invoice.number}.pdf"
      end)
    end

    test "waits for Jennie to send it otherwise", ctx do
      order = placed_order(payment_terms: :invoice)

      {:ok, invoice} = invoice(%{order_id: order.id}, ctx)

      refute invoice.sent_at
      Swoosh.TestAssertions.assert_no_email_sent()

      {:ok, sent} = Payments.send_invoice(invoice, %{message: nil}, actor: ctx.admin)

      assert sent.sent_at
      assert Decimal.equal?(sent.amount, invoice.amount)

      Swoosh.TestAssertions.assert_email_sent(fn email ->
        assert email.subject =~ "Invoice #{invoice.number}"
        assert [%{filename: "invoice-" <> _}] = email.attachments
      end)
    end

    test "gives the payee and IBAN frozen on the invoice, so a resend matches its PDF", ctx do
      order = placed_order(payment_terms: :invoice)
      {:ok, invoice} = invoice(%{order_id: order.id}, ctx)

      frozen_seller = %{invoice.content["seller"] | "name" => "Eden Flowers Ab", "iban" => "FI21 1234 5600 0007 85"}
      invoice = Ash.Seed.update!(invoice, %{content: %{invoice.content | "seller" => frozen_seller}})

      {:ok, _sent} = Payments.send_invoice(invoice, %{message: nil}, actor: ctx.admin)

      Swoosh.TestAssertions.assert_email_sent(fn email ->
        assert email.text_body =~ "Eden Flowers Ab"
        assert email.text_body =~ "FI21 1234 5600 0007 85"
      end)
    end

    test "names a booking's course in the invoice's language", ctx do
      registration = generate(course_registration(status: :confirmed, payment_terms: :invoice, locale: "en-GB"))

      {:ok, invoice} =
        invoice(%{course_registration_id: registration.id}, ctx, %{locale: "sv-FI", email_customer?: true})

      assert invoice.__metadata__.emailed?

      Swoosh.TestAssertions.assert_email_sent(fn email ->
        assert [%{filename: "faktura-" <> _}] = email.attachments
      end)
    end

    test "can't be built without what was paid on it", ctx do
      order = placed_order(payment_terms: :invoice)
      {:ok, invoice} = invoice(%{order_id: order.id}, ctx)
      loaded = SendInvoice.load_for_email(invoice)

      assert_raise FunctionClauseError, fn -> Email.invoice(%{loaded | amount_paid: %Ash.NotLoaded{}}) end
    end

    test "points the order details to it, and to an invoice for the rest", ctx do
      order = placed_order(payment_terms: :invoice, payment_intent_id: nil)
      {:ok, invoice} = invoice(%{order_id: order.id}, ctx, %{amount: "30.00", email_customer?: true})
      Swoosh.TestAssertions.assert_email_sent()

      {:ok, _order} = Orders.send_order_details_email(order, %{}, actor: ctx.admin)

      Swoosh.TestAssertions.assert_email_sent(fn email ->
        assert email.text_body =~
                 "My invoice #{invoice.number} is due on #{Format.weekday_date(invoice.due_date, "en-GB")}. " <>
                   "I'll send you an invoice for the rest after you've collected your order."
      end)
    end
  end

  describe "for a cancelled purchase" do
    test "made after the cancel bills the cancellation charge and says so; one made before doesn't", ctx do
      order = placed_order(payment_terms: :invoice, payment_intent_id: nil)
      {:ok, earlier} = invoice(%{order_id: order.id}, ctx, %{amount: "20.00"})
      # Made in an earlier second than the cancel, which cancelled_at is stamped to.
      earlier = Ash.Seed.update!(earlier, %{inserted_at: DateTime.add(earlier.inserted_at, -60)})

      {:ok, _order} =
        Orders.cancel_order(order, %{cancellation_charge: "30.00", email_customer?: false}, actor: ctx.admin)

      {:ok, charge} = invoice(%{order_id: order.id}, ctx, %{email_customer?: true})

      assert Decimal.equal?(charge.amount, "10.00")

      Swoosh.TestAssertions.assert_email_sent(fn email ->
        assert email.text_body =~
                 "My invoice for the cancellation charge for your order for Wednesday 10.6.2026 is attached."
      end)

      {:ok, _sent} = Payments.send_invoice(earlier, %{message: nil}, actor: ctx.admin)

      Swoosh.TestAssertions.assert_email_sent(fn email ->
        assert email.text_body =~ "Thank you for your order for Wednesday 10.6.2026. My invoice is attached."
      end)
    end

    for {charge, sent?, plan, line} <- [
          {"30.00", true, "replace", "I'll cancel my earlier invoice and send you a new one for it."},
          {"88.50", true, "stand", "My earlier invoice already asks for it, so please pay that one."},
          {"0", true, "cancel", "I'll cancel my earlier invoice, so you don't need to pay it."},
          {"30.00", false, "none", "I'll send you an invoice for it."}
        ] do
      test "cancelled with a charge of #{charge}, #{if sent?, do: "sent", else: "unsent"} invoice: #{plan}", ctx do
        order = placed_order(payment_terms: :invoice, payment_intent_id: nil)
        {:ok, _invoice} = invoice(%{order_id: order.id}, ctx, %{email_customer?: unquote(sent?)})
        if unquote(sent?), do: Swoosh.TestAssertions.assert_email_sent()

        {:ok, _order} = Orders.cancel_order(order, %{cancellation_charge: unquote(charge)}, actor: ctx.admin)

        [job] = all_enqueued(worker: SendCancelledEmail)
        assert job.args["earlier_invoices"] == unquote(plan)
        assert :ok = perform_job(SendCancelledEmail, job.args)

        Swoosh.TestAssertions.assert_email_sent(fn email -> assert email.text_body =~ unquote(line) end)
      end
    end
  end

  describe "cancelling one" do
    defp cancel(invoice, ctx, attrs \\ %{}) do
      Payments.cancel_invoice(Map.put(attrs, :invoice_id, invoice.id), actor: ctx.admin)
    end

    test "issues a credit note numbered next in the same series", ctx do
      order = placed_order(payment_terms: :invoice)
      {:ok, invoice} = invoice(%{order_id: order.id}, ctx, %{amount: "30.00"})

      {:ok, credit_note} = cancel(invoice, ctx, %{reason: "Wrong amount"})
      {:ok, next} = invoice(%{order_id: order.id}, ctx)

      assert credit_note.number == invoice.number + 1
      assert credit_note.credit_date == ShopTime.today()
      assert next.number == credit_note.number + 1
      assert Ash.load!(invoice, :status).status == :cancelled
    end

    test "no longer counts it as invoiced, so the next invoice asks for the whole Balance", ctx do
      order = placed_order(payment_terms: :invoice, payment_intent_id: nil)
      {:ok, invoice} = invoice(%{order_id: order.id}, ctx, %{amount: "30.00"})

      {:ok, _credit_note} = cancel(invoice, ctx)

      order = Ash.load!(order, [:uninvoiced_balance, :open_invoices], authorize?: false)
      assert Decimal.equal?(order.uninvoiced_balance, "88.50")
      assert order.open_invoices == []
      assert error_message(pay(order, "30.00", invoice, ctx)) =~ "is cancelled"
    end

    test "is refused once anything is paid on it, until that is undone", ctx do
      order = placed_order(payment_terms: :invoice, payment_intent_id: nil)
      {:ok, paid} = invoice(%{order_id: order.id}, ctx, %{amount: "20.00"})
      {:ok, part_paid} = invoice(%{order_id: order.id}, ctx, %{amount: "30.00"})
      {:ok, order} = pay(order, "20.00", paid, ctx)
      {:ok, order} = pay(order, "10.00", part_paid, ctx)

      assert error_message(cancel(paid, ctx)) =~ "A paid invoice can't be cancelled"
      assert error_message(cancel(part_paid, ctx)) =~ "Undo them first"

      ten = Enum.find(Ash.load!(order, :payments, authorize?: false).payments, &Decimal.equal?(&1.amount, "10.00"))
      {:ok, _order} = Orders.undo_payment(order, ten.id, actor: ctx.admin)

      assert {:ok, _credit_note} = cancel(part_paid, ctx)
    end

    test "only once", ctx do
      order = placed_order(payment_terms: :invoice)
      {:ok, invoice} = invoice(%{order_id: order.id}, ctx)
      {:ok, credit_note} = cancel(invoice, ctx)

      assert error_message(cancel(invoice, ctx)) =~ "Credit note #{credit_note.number} already cancels"
    end

    test "emails the credit note in the invoice's language when asked", ctx do
      order = placed_order(payment_terms: :invoice, locale: "en-GB")
      {:ok, invoice} = invoice(%{order_id: order.id}, ctx, %{locale: "sv-FI"})

      {:ok, credit_note} = cancel(invoice, ctx, %{email_customer?: true, message: "Förlåt för krånglet!"})

      assert credit_note.__metadata__.emailed?
      assert credit_note.sent_at

      Swoosh.TestAssertions.assert_email_sent(fn email ->
        assert email.to == [{"", "ada@example.com"}]
        assert email.subject =~ "#{invoice.number}"
        assert email.text_body =~ "Förlåt för krånglet!"
        assert [%{filename: filename, content_type: "application/pdf"}] = email.attachments
        assert filename == "kreditnota-#{credit_note.number}.pdf"
      end)
    end

    test "waits for Jennie to send it otherwise", ctx do
      order = placed_order(payment_terms: :invoice)
      {:ok, invoice} = invoice(%{order_id: order.id}, ctx)
      {:ok, credit_note} = cancel(invoice, ctx)

      refute credit_note.sent_at
      Swoosh.TestAssertions.assert_no_email_sent()

      {:ok, sent} = Payments.send_credit_note(credit_note, %{message: nil}, actor: ctx.admin)

      assert sent.sent_at

      Swoosh.TestAssertions.assert_email_sent(fn email ->
        assert email.text_body =~ "I've cancelled invoice #{invoice.number}"
        assert [%{filename: "credit-note-" <> _}] = email.attachments
      end)
    end
  end

  describe "once past its due date" do
    defp due(invoice, days_from_today),
      do: Ash.Seed.update!(invoice, %{due_date: Date.add(ShopTime.today(), days_from_today)})

    defp overdue?(record), do: Ash.load!(record, :overdue?, authorize?: false, reuse_values?: false).overdue?

    test "is overdue while open, from the day after its due date", ctx do
      order = placed_order(payment_terms: :invoice, payment_intent_id: nil)
      {:ok, paid} = invoice(%{order_id: order.id}, ctx, %{amount: "20.00"})
      {:ok, cancelled} = invoice(%{order_id: order.id}, ctx, %{amount: "20.00"})
      {:ok, part_paid} = invoice(%{order_id: order.id}, ctx, %{amount: "20.00"})
      {:ok, due_today} = invoice(%{order_id: order.id}, ctx, %{amount: "20.00"})

      {:ok, order} = pay(order, "20.00", paid, ctx)
      {:ok, _order} = pay(order, "5.00", part_paid, ctx)
      {:ok, _credit_note} = cancel(cancelled, ctx)
      Enum.each([paid, cancelled, part_paid], &due(&1, -1))

      refute overdue?(paid)
      refute overdue?(cancelled)
      assert overdue?(part_paid)
      refute overdue?(due(due_today, 0))
    end

    test "puts its purchase under Payment overdue, while an invoiced Balance waits for its own due date", ctx do
      handed_over = Date.add(ShopTime.today(), -30)
      order = placed_order(payment_terms: :invoice, fulfillment_status: :fulfilled, fulfillment_date: handed_over)
      payment_overdue? = fn -> Ash.load!(order, :payment_overdue?, authorize?: false).payment_overdue? end

      assert payment_overdue?.()

      {:ok, invoice} = invoice(%{order_id: order.id}, ctx)
      refute payment_overdue?.()

      due(invoice, -1)
      assert payment_overdue?.()
      assert order.id in Enum.map(Orders.list_unsettled_orders!(actor: ctx.admin), & &1.id)
    end

    test "resending it emails the same PDF with a friendly reminder, logged as one", ctx do
      order = placed_order(payment_terms: :invoice)
      {:ok, invoice} = invoice(%{order_id: order.id}, ctx, %{email_customer?: true})

      Swoosh.TestAssertions.assert_email_sent(subject: "Invoice #{invoice.number} for your order for Wednesday 10.6.")

      invoice = due(invoice, -1)
      {:ok, _sent} = Payments.send_invoice(invoice, %{message: "Hope all went well!"}, actor: ctx.admin)

      Swoosh.TestAssertions.assert_email_sent(fn email ->
        assert email.subject =~ "A reminder about invoice #{invoice.number}"
        assert email.text_body =~ "friendly reminder that it was due on"
        assert email.text_body =~ "Hope all went well!"
        assert [%{filename: filename}] = email.attachments
        assert filename == "invoice-#{invoice.number}.pdf"
      end)

      versions = Ash.load!(invoice, :paper_trail_versions, authorize?: false).paper_trail_versions
      assert versions |> Enum.sort_by(& &1.version_inserted_at, DateTime) |> Enum.map(& &1.reminder) == [false, true]
    end

    test "a reminder for one paid in part asks only for the rest", ctx do
      order = placed_order(payment_terms: :invoice, payment_intent_id: nil)
      {:ok, invoice} = invoice(%{order_id: order.id}, ctx)
      {:ok, _order} = pay(order, "20.00", invoice, ctx)

      {:ok, _sent} = Payments.send_invoice(due(invoice, -1), %{message: nil}, actor: ctx.admin)

      Swoosh.TestAssertions.assert_email_sent(fn email ->
        assert email.text_body =~ "and 68,50\u00A0€ of it is still to pay. Thank you for what you've paid so far."
        assert email.text_body =~ "Invoice amount  88,50\u00A0€\nStill to pay  68,50\u00A0€"
      end)
    end

    test "can't be sent once paid or cancelled", ctx do
      order = placed_order(payment_terms: :invoice, payment_intent_id: nil)
      {:ok, paid} = invoice(%{order_id: order.id}, ctx, %{amount: "20.00"})
      {:ok, cancelled} = invoice(%{order_id: order.id}, ctx, %{amount: "20.00"})
      {:ok, _order} = pay(order, "20.00", paid, ctx)
      {:ok, _credit_note} = cancel(cancelled, ctx)

      assert error_message(Payments.send_invoice(paid, %{}, actor: ctx.admin)) =~ "This invoice is paid"
      assert error_message(Payments.send_invoice(cancelled, %{}, actor: ctx.admin)) =~ "This invoice is cancelled"
      Swoosh.TestAssertions.assert_no_email_sent()
    end

    # Jennie decides whether to nudge a late payer (TASK-168): no trigger or
    # scheduled job may email an invoice or a credit note.
    test "is never emailed automatically" do
      documents = [Invoice, Edenflowers.Payments.CreditNote]

      triggered =
        for domain <- Application.fetch_env!(:edenflowers, :ash_domains),
            resource <- Ash.Domain.Info.resources(domain),
            AshOban in Spark.extensions(resource),
            _trigger <- AshOban.Info.oban_triggers(resource),
            do: resource

      assert Enum.filter(triggered, &(&1 in documents)) == []

      sends_documents = ~r/send_invoice|send_credit_note|Email\.invoice|Email\.credit_note|SendInvoice|SendCreditNote/

      workers = Path.wildcard("lib/edenflowers/**/workers/*.ex")
      assert workers != []
      assert Enum.filter(workers, &(File.read!(&1) =~ sends_documents)) == []
    end
  end

  test "keeps the buyer details it was made with", ctx do
    order = placed_order(payment_terms: :invoice) |> Ash.Seed.update!(@company)

    {:ok, invoice} = invoice(%{order_id: order.id}, ctx)
    {:ok, _} = Orders.update_order_business_details(order, %{company_name: "Ruusu Ab"}, actor: ctx.admin)

    invoice = Ash.get!(Invoice, invoice.id, authorize?: false)
    assert invoice.company_name == "Kukka Oy"
    assert invoice.business_id == "2944459-6"
    assert invoice.buyer_name == "Ada Lovelace"
    assert invoice.buyer_email == "ada@example.com"
  end
end
