defmodule Edenflowers.EmailTest do
  use Edenflowers.DataCase
  import Generator

  alias Edenflowers.Email
  alias Edenflowers.Store.Order

  describe "order_confirmation/1 - basic pickup order" do
    setup do
      tax_rate = generate(tax_rate(percentage: "0.255"))
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "49.99"))

      fulfillment_option =
        generate(
          fulfillment_option(
            name: "Pickup",
            fulfillment_method: :pickup,
            rate_type: :fixed,
            base_price: "4.99",
            tax_rate_id: tax_rate.id
          )
        )

      order = Ash.Seed.seed!(Order, %{
        customer_name: "John Doe",
        customer_email: "john@example.com",
        gift: false,
        fulfillment_option_id: fulfillment_option.id,
        fulfillment_date: ~D[2025-12-25],
        fulfillment_amount: Decimal.new("4.99"),
        state: :order,
        payment_status: :paid,
        ordered_at: DateTime.utc_now()
      })

      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage,
          quantity: 2
        )
      )

      # Load order with all required data
      order =
        order.id
        |> Order.get_by_id!()
        |> Ash.load!([:line_items, :fulfillment_option, :line_total, :line_tax_amount, :discount_amount, :tax_amount, :total, :order_reference])

      %{order: order}
    end

    test "returns a Swoosh.Email struct", %{order: order} do
      email = Email.order_confirmation(order)
      assert %Swoosh.Email{} = email
    end

    test "sets the correct recipient", %{order: order} do
      email = Email.order_confirmation(order)
      assert email.to == [{"John Doe", "john@example.com"}]
    end

    test "sets the correct sender", %{order: order} do
      email = Email.order_confirmation(order)
      assert email.from == {"Jennie", "info@edenflowers.fi"}
    end

    test "sets the correct subject", %{order: order} do
      email = Email.order_confirmation(order)
      assert email.subject == "Thank you for your order"
    end

    test "includes customer name in greeting", %{order: order} do
      email = Email.order_confirmation(order)
      assert email.text_body =~ "Hi John Doe"
    end

    test "includes order reference", %{order: order} do
      email = Email.order_confirmation(order)
      assert email.text_body =~ "Order Reference: #{order.order_reference}"
    end

    test "includes order date", %{order: order} do
      email = Email.order_confirmation(order)
      assert email.text_body =~ "Order Date:"
      # Just check it contains a formatted date string
      assert email.text_body =~ ~r/\d{4}/
    end

    test "includes line items with product name and quantity", %{order: order} do
      email = Email.order_confirmation(order)
      line_item = List.first(order.line_items)

      assert email.text_body =~ line_item.product_name
      assert email.text_body =~ "× #{line_item.quantity}"
    end

    test "includes prices with Cldr currency formatting", %{order: order} do
      email = Email.order_confirmation(order)
      # Check that currency is formatted with € symbol (Cldr format)
      assert email.text_body =~ "€"
      assert email.text_body =~ "Subtotal:"
      assert email.text_body =~ "Tax:"
      assert email.text_body =~ "TOTAL:"
    end

    test "includes fulfillment method", %{order: order} do
      email = Email.order_confirmation(order)
      assert email.text_body =~ "Method: Pickup"
    end

    test "includes fulfillment date with Cldr formatting", %{order: order} do
      email = Email.order_confirmation(order)
      assert email.text_body =~ "Date:"
      # Cldr long format includes month name
      assert email.text_body =~ "December"
    end

    test "does not include delivery address for pickup orders", %{order: order} do
      email = Email.order_confirmation(order)
      refute email.text_body =~ "Delivery Address:"
    end

    test "does not include gift message section when gift is false", %{order: order} do
      email = Email.order_confirmation(order)
      refute email.text_body =~ "GIFT MESSAGE"
    end
  end

  describe "order_confirmation/1 - delivery order" do
    setup do
      tax_rate = generate(tax_rate(percentage: "0.255"))
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "39.99"))

      fulfillment_option =
        generate(
          fulfillment_option(
            name: "Delivery",
            fulfillment_method: :delivery,
            rate_type: :dynamic,
            base_price: "5.00",
            price_per_km: "1.50",
            free_dist_km: 5,
            max_dist_km: 20,
            tax_rate_id: tax_rate.id
          )
        )

      order = Ash.Seed.seed!(Order, %{
        customer_name: "Jane Smith",
        customer_email: "jane@example.com",
        gift: false,
        fulfillment_option_id: fulfillment_option.id,
        fulfillment_date: ~D[2025-12-24],
        fulfillment_amount: Decimal.new("12.50"),
        delivery_address: "123 Main Street, Helsinki",
        calculated_address: "123 Main Street, 00100 Helsinki, Finland",
        recipient_name: "Jane Smith",
        recipient_phone_number: "+358401234567",
        delivery_instructions: "Leave at the door",
        state: :order,
        payment_status: :paid,
        ordered_at: DateTime.utc_now()
      })

      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage,
          quantity: 1
        )
      )

      order =
        order.id
        |> Order.get_by_id!()
        |> Ash.load!([:line_items, :fulfillment_option, :line_total, :line_tax_amount, :discount_amount, :tax_amount, :total, :order_reference])

      %{order: order}
    end

    test "includes delivery method", %{order: order} do
      email = Email.order_confirmation(order)
      assert email.text_body =~ "Method: Delivery"
    end

    test "includes recipient name for delivery", %{order: order} do
      email = Email.order_confirmation(order)
      assert email.text_body =~ "Recipient: Jane Smith"
    end

    test "includes delivery address", %{order: order} do
      email = Email.order_confirmation(order)
      assert email.text_body =~ "Delivery Address: 123 Main Street, 00100 Helsinki, Finland"
    end

    test "includes recipient phone number", %{order: order} do
      email = Email.order_confirmation(order)
      assert email.text_body =~ "Phone: +358401234567"
    end

    test "includes delivery instructions", %{order: order} do
      email = Email.order_confirmation(order)
      assert email.text_body =~ "Instructions: Leave at the door"
    end
  end

  describe "order_confirmation/1 - gift order" do
    setup do
      tax_rate = generate(tax_rate(percentage: "0.255"))
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "59.99"))

      fulfillment_option =
        generate(
          fulfillment_option(
            name: "Pickup",
            fulfillment_method: :pickup,
            rate_type: :fixed,
            base_price: "0.00",
            tax_rate_id: tax_rate.id
          )
        )

      order = Ash.Seed.seed!(Order, %{
        customer_name: "Sarah Johnson",
        customer_email: "sarah@example.com",
        gift: true,
        gift_message: "Happy Birthday! Love you lots.",
        recipient_name: "Mom",
        fulfillment_option_id: fulfillment_option.id,
        fulfillment_date: ~D[2025-12-25],
        fulfillment_amount: Decimal.new("0.00"),
        state: :order,
        payment_status: :paid,
        ordered_at: DateTime.utc_now()
      })

      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage,
          quantity: 1
        )
      )

      order =
        order.id
        |> Order.get_by_id!()
        |> Ash.load!([:line_items, :fulfillment_option, :line_total, :line_tax_amount, :discount_amount, :tax_amount, :total, :order_reference])

      %{order: order}
    end

    test "includes gift message section", %{order: order} do
      email = Email.order_confirmation(order)
      assert email.text_body =~ "GIFT MESSAGE"
    end

    test "includes recipient name in gift section", %{order: order} do
      email = Email.order_confirmation(order)
      assert email.text_body =~ "To: Mom"
    end

    test "includes gift message text", %{order: order} do
      email = Email.order_confirmation(order)
      assert email.text_body =~ "Happy Birthday! Love you lots."
    end
  end

  describe "order_confirmation/1 - order with promotion" do
    setup do
      tax_rate = generate(tax_rate(percentage: "0.255"))
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "100.00"))
      promotion = generate(promotion(discount_percentage: "0.15"))

      fulfillment_option =
        generate(
          fulfillment_option(
            name: "Pickup",
            fulfillment_method: :pickup,
            rate_type: :fixed,
            base_price: "5.00",
            tax_rate_id: tax_rate.id
          )
        )

      order = Ash.Seed.seed!(Order, %{
        customer_name: "Bob Wilson",
        customer_email: "bob@example.com",
        gift: false,
        promotion_id: promotion.id,
        fulfillment_option_id: fulfillment_option.id,
        fulfillment_date: ~D[2025-12-25],
        fulfillment_amount: Decimal.new("5.00"),
        state: :order,
        payment_status: :paid,
        ordered_at: DateTime.utc_now()
      })

      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage,
          quantity: 2,
          promotion_id: promotion.id
        )
      )

      order =
        order.id
        |> Order.get_by_id!()
        |> Ash.load!([:line_items, :fulfillment_option, :promotion, :line_total, :line_tax_amount, :discount_amount, :tax_amount, :total, :order_reference])

      %{order: order}
    end

    test "includes discount amount when promotion is applied", %{order: order} do
      email = Email.order_confirmation(order)

      # Verify discount is present and greater than zero
      assert Decimal.compare(order.discount_amount, 0) == :gt
      assert email.text_body =~ "Discount:"
    end
  end
end
