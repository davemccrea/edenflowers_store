defmodule Edenflowers.Orders.Workers.SendOrderConfirmationEmailTest do
  use Edenflowers.DataCase
  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Workers.SendOrderConfirmationEmail

  @moduletag :typst

  test "delivers the confirmation email with the PDF receipt attached and marks the order" do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id, price: "39.90"))

    order =
      generate(
        order(
          locale: "en-GB",
          customer_name: "Anna Lindqvist",
          customer_email: "anna@example.com",
          order_reference: "EF-TEST-OC1",
          ordered_at: ~U[2026-05-15 12:00:00Z],
          fulfillment_method: :pickup,
          fulfillment_date: ~D[2026-05-20],
          fulfillment_fee: "0"
        )
      )

    _line_item = generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 1))

    assert :ok = perform_job(SendOrderConfirmationEmail, %{"order_id" => order.id})

    assert_email_sent(fn email ->
      assert email.to == [{"", "anna@example.com"}]
      assert email.subject =~ "EF-TEST-OC1"
      assert email.text_body =~ "Anna"
      assert email.text_body =~ "EF-TEST-OC1"
      assert email.html_body in [nil, ""]
      assert [%Swoosh.Attachment{content_type: "application/pdf"}] = email.attachments
    end)

    reloaded = Orders.get_order_by_id!(order.id, authorize?: false)
    assert reloaded.receipt_emailed_at != nil
    assert reloaded.receipt_sha256 =~ ~r/^[0-9a-f]{64}$/
  end

  test "renders the email in the order's locale" do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id, price: "39.90"))

    order =
      generate(
        order(
          locale: "fi",
          customer_name: "Anna Lindqvist",
          customer_email: "anna@example.com",
          order_reference: "EF-TEST-OC2",
          ordered_at: ~U[2026-05-15 12:00:00Z],
          fulfillment_method: :pickup,
          fulfillment_date: ~D[2026-05-20],
          fulfillment_fee: "0"
        )
      )

    _line_item = generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 1))

    assert :ok = perform_job(SendOrderConfirmationEmail, %{"order_id" => order.id})

    assert_email_sent(fn email ->
      assert email.subject =~ "Tilausvahvistus"
      assert not (email.subject =~ "Order Confirmation")
    end)
  end
end
