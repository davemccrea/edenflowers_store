defmodule Edenflowers.Orders.Order.Changes.SendReceiptEmailTest do
  use Edenflowers.DataCase, async: true
  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Workers.SendReceiptEmail

  @moduletag :typst

  for kind <- [:flowers, :gift_voucher] do
    @kind kind
    test "a queued #{@kind} confirmation sends nothing if the order was cancelled before it ran" do
      admin = generate(admin_user())

      order =
        case @kind do
          :flowers ->
            placed_order(payment_intent_id: nil)

          :gift_voucher ->
            Orders.sell_gift_voucher!(%{customer_name: "Anna", customer_email: "a@example.com", amount: 50},
              actor: admin
            )
        end

      order = Orders.record_payment!(order, "50.00", :cash, actor: admin)
      Orders.cancel_order!(order, %{email_customer?: false}, actor: admin)

      assert {:ok, _} = perform_job(SendReceiptEmail, %{"primary_key" => %{"id" => order.id}})
      assert_no_email_sent()
      refute Orders.get_order_by_id!(order.id, authorize?: false).receipt_emailed_at
    end
  end

  for voucher_amount <- ["20.00", "88.50"] do
    @voucher_amount voucher_amount
    test "a subscription receipt uses actual voucher payments of #{@voucher_amount}" do
      voucher = generate(gift_voucher(amount: Decimal.new("100.00")))
      order = placed_order(origin: :subscription, gift_voucher_id: voucher.id, payment_intent_id: nil)

      generate(
        payment(order_id: order.id, method: :voucher, gift_voucher_id: voucher.id, amount: Decimal.new(@voucher_amount))
      )

      card_amount = Decimal.sub("88.50", @voucher_amount)
      if Decimal.positive?(card_amount), do: generate(payment(order_id: order.id, amount: card_amount))

      assert {:ok, _} = perform_job(SendReceiptEmail, %{"primary_key" => %{"id" => order.id}})

      assert_email_sent(fn email ->
        if Decimal.positive?(card_amount) do
          assert email.text_body =~ "Your card was charged 68,50 €"
          assert email.text_body =~ "Paid with your gift voucher: 20,00 €."
        else
          refute email.text_body =~ "Your card was charged"
          assert email.text_body =~ "Your gift voucher paid 88,50 €"
        end
      end)
    end
  end

  test "delivers the confirmation email with the PDF receipt attached and marks the order" do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id, price: "39.90"))

    order =
      generate(
        order(
          state: :placed,
          locale: "en-GB",
          customer_name: "Anna Lindqvist",
          customer_email: "anna@example.com",
          order_reference: "TEST-OC1",
          ordered_at: ~U[2026-05-15 12:00:00Z],
          fulfillment_method: :pickup,
          fulfillment_date: ~D[2026-05-20],
          quoted_fulfillment_fee: "0"
        )
      )

    _line_item = generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 1))
    _payment = generate(payment(order_id: order.id, amount: Decimal.new("39.90")))

    assert {:ok, _order} = perform_job(SendReceiptEmail, %{"primary_key" => %{"id" => order.id}})

    assert_email_sent(fn email ->
      assert email.to == [{"", "anna@example.com"}]
      assert email.bcc == [{"Jennie", "info+copy@edenflowers.fi"}]
      assert email.subject =~ "Your Eden Flowers order for"
      assert email.text_body =~ "Anna"
      assert email.html_body in [nil, ""]
      assert [%Swoosh.Attachment{content_type: "application/pdf"}] = email.attachments
    end)

    reloaded = Orders.get_order_by_id!(order.id, authorize?: false)
    assert reloaded.receipt_emailed_at != nil
  end

  test "renders the email in the order's locale" do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id, price: "39.90"))

    order =
      generate(
        order(
          state: :placed,
          locale: "fi",
          customer_name: "Anna Lindqvist",
          customer_email: "anna@example.com",
          order_reference: "TEST-OC2",
          ordered_at: ~U[2026-05-15 12:00:00Z],
          fulfillment_method: :pickup,
          fulfillment_date: ~D[2026-05-20],
          quoted_fulfillment_fee: "0"
        )
      )

    _line_item = generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 1))
    _payment = generate(payment(order_id: order.id, amount: Decimal.new("39.90")))

    assert {:ok, _order} = perform_job(SendReceiptEmail, %{"primary_key" => %{"id" => order.id}})

    assert_email_sent(fn email ->
      assert email.subject =~ "Eden Flowers -tilauksesi:"
      assert not (email.subject =~ "Your receipt")
    end)
  end

  test "renders the email in a region-qualified locale that has no exact Gettext catalog" do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id, price: "39.90"))

    order =
      generate(
        order(
          state: :placed,
          locale: "sv-FI",
          customer_name: "Anna Lindqvist",
          customer_email: "anna@example.com",
          order_reference: "TEST-OC3",
          ordered_at: ~U[2026-05-15 12:00:00Z],
          fulfillment_method: :pickup,
          fulfillment_date: ~D[2026-05-20],
          quoted_fulfillment_fee: "0"
        )
      )

    _line_item = generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 1))
    _payment = generate(payment(order_id: order.id, amount: Decimal.new("39.90")))

    assert {:ok, _order} = perform_job(SendReceiptEmail, %{"primary_key" => %{"id" => order.id}})

    assert_email_sent(fn email ->
      assert email.subject =~ "Din Eden Flowers-beställning för"
      assert not (email.subject =~ "Your receipt")
    end)
  end
end
