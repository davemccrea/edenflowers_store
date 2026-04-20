defmodule EdenflowersWeb.CheckoutLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import PhoenixTest
  import Generator
  import Mox

  alias Edenflowers.Store.{Order, LineItem}

  setup :verify_on_exit!

  setup do
    product = generate(product())
    variant = generate(product_variant(%{product_id: product.id}))
    generate(fulfillment_option())

    order = generate(order())

    {:ok, _line_item} =
      LineItem.add_item(%{
        order_id: order.id,
        product_id: product.id,
        product_variant_id: variant.id,
        product_name: product.name,
        product_image_slug: variant.image_slug,
        quantity: 1,
        unit_price: variant.price,
        tax_rate: Decimal.new("0.24")
      })

    order = Order.get_for_checkout!(order.id, actor: nil)

    mock_payment_intent = %{
      id: "pi_test_#{:rand.uniform(1_000_000)}",
      client_secret: "pi_test_secret_#{:rand.uniform(1_000_000)}"
    }

    stub(Edenflowers.StripeAPI.Mock, :create_payment_intent, fn _order ->
      {:ok, mock_payment_intent}
    end)

    stub(Edenflowers.StripeAPI.Mock, :retrieve_payment_intent, fn _order ->
      {:ok, mock_payment_intent}
    end)

    stub(Edenflowers.StripeAPI.Mock, :update_payment_intent, fn _order ->
      {:ok, mock_payment_intent}
    end)

    %{order: order}
  end

  describe "Step 1: Your Details" do
    test "successfully submits and progresses to step 2", %{conn: conn, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/checkout")
      |> fill_in("Your Name *", with: "John Doe")
      |> fill_in("Email *", with: "john@example.com")
      |> click_button("Next")
      |> assert_has("h1", text: "Gift Options")
    end
  end

  describe "Step 2: Gift Options" do
    setup %{conn: conn, order: order} do
      session =
        conn
        |> Plug.Test.init_test_session(%{order_id: order.id})
        |> visit("/checkout")
        |> fill_in("Your Name *", with: "John Doe")
        |> fill_in("Email *", with: "john@example.com")
        |> click_button("Next")

      %{session: session}
    end

    test "successfully submits and progresses to step 3", %{session: session} do
      session
      |> click_button("Next")
      |> assert_has("h1", text: "Delivery Information")
    end
  end
end
