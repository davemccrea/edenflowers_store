defmodule Edenflowers.Payments.InvoiceTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Courses
  alias Edenflowers.Orders
  alias Edenflowers.Payments
  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.ReferenceNumber
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
      order = placed_order(payment_terms: :invoice, fulfillment_status: :fulfilled, business_customer: true)

      assert error_message(invoice(%{order_id: order.id}, ctx)) =~ "company name, Y-tunnus and billing address"

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
