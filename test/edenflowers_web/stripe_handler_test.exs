defmodule EdenflowersWeb.StripeHandlerTest do
  use Edenflowers.DataCase

  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Store.Order

  describe "StripeHandler" do
    test "updates order and sends a confirmation email" do
      # Clean up any existing jobs from previous tests
      Edenflowers.Repo.delete_all(Oban.Job)

      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id))
      fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate.id))

      {:ok, fulfillment_amount} = Edenflowers.Fulfillments.calculate_price(fulfillment_option)

      {:ok, user} = Edenflowers.Accounts.User.upsert("john.smith@example.com", "John Smith", authorize?: false)

      order =
        Ash.Seed.seed!(Order, %{
          customer_name: "John Smith",
          customer_email: "john.smith@example.com",
          user_id: user.id,
          fulfillment_option_id: fulfillment_option.id,
          fulfillment_date: Date.utc_today(),
          fulfillment_amount: fulfillment_amount
        })

      _line_item =
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

      assert :ok =
               EdenflowersWeb.StripeHandler.handle_event(%Stripe.Event{
                 type: "payment_intent.succeeded",
                 data: %{object: %{metadata: %{"order_id" => order.id}}}
               })

      order = Order.get_by_id!(order.id, authorize?: false)
      assert order.state == :order
      assert order.payment_status == :paid

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)

      assert_email_sent()
    end
  end
end
