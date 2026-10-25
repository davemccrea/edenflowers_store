defmodule EdenflowersWeb.Checkout.CheckoutHappyPathTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator
  import Mox
  import Swoosh.TestAssertions

  alias Edenflowers.Orders
  alias EdenflowersWeb.Webhooks.StripeHandler

  @moduletag :typst

  setup :verify_on_exit!

  setup %{conn: conn} do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id))

    fulfillment_option =
      generate(
        fulfillment_option(
          tax_rate_id: tax_rate.id,
          fulfillment_method: :pickup,
          rate_type: :fixed,
          base_price: "0.00"
        )
      )

    order = generate(order())

    Orders.add_line_item!(order.id, variant.id, 1, authorize?: false)

    payment_intent = %{
      id: "pi_test_#{:rand.uniform(1_000_000)}",
      client_secret: "pi_test_secret_#{:rand.uniform(1_000_000)}"
    }

    stub(Edenflowers.External.StripeAPI.Mock, :create_payment_intent, fn _amount, _metadata, _customer ->
      {:ok, payment_intent}
    end)

    stub(Edenflowers.External.StripeAPI.Mock, :retrieve_payment_intent, fn _order -> {:ok, payment_intent} end)

    stub(Edenflowers.External.StripeAPI.Mock, :update_payment_intent, fn _payment_intent_id, _amount_cents ->
      {:ok, payment_intent}
    end)

    conn = Plug.Test.init_test_session(conn, %{order_id: order.id})

    %{conn: conn, order: order, fulfillment_option: fulfillment_option}
  end

  test "completes a pickup checkout from step 1 through payment to confirmation email", %{
    conn: conn,
    order: order,
    fulfillment_option: fulfillment_option
  } do
    {:ok, view, _html} = live(conn, ~p"/checkout")

    view
    |> form("#checkout-form-1", %{
      "form" => %{
        "customer_name" => "Jane Doe",
        "customer_email" => "jane@example.com"
      }
    })
    |> render_submit()

    assert render(view) =~ "Gift options"

    # Not a gift, so the defaults are fine.
    view
    |> form("#checkout-form-2", %{"form" => %{"gift" => "false"}})
    |> render_submit()

    assert render(view) =~ ~r{<h2[^>]*>.*?<span>Delivery</span>.*?</h2>}s

    view
    |> element("#checkout-form-3a")
    |> render_change(%{"form" => %{"fulfillment_option_id" => fulfillment_option.id}})

    fulfillment_date = Edenflowers.ShopTime.today() |> Date.add(7) |> Date.to_string()

    view
    |> element("#checkout-form-3b")
    |> render_submit(%{
      "form" => %{
        "recipient_phone_number" => "045 1234567",
        "fulfillment_date" => fulfillment_date
      }
    })

    assert render(view) =~ "Payment"

    # Step 4: submit the payment form. In production, the Stripe JS hook
    # handles the confirmation; here the mocked update_payment_intent is
    # what the server touches. The webhook below drives the rest.
    view
    |> element("#checkout-form-4")
    |> render_submit()

    # Simulate Stripe firing payment_intent.succeeded — this finalizes the
    # order and enqueues the confirmation email Oban job.
    assert :ok =
             StripeHandler.handle_event(payment_intent_succeeded_event(order.id))

    finalized = Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])
    assert finalized.state == :placed
    assert finalized.payment_status == :paid

    # The receipt and the shop's new-order email.
    assert %{success: 2, failure: 0} = Oban.drain_queue(queue: :default)

    assert_email_sent(fn email ->
      assert email.to == [{"", "jane@example.com"}]
      assert email.subject =~ "Your Eden Flowers order for"
      assert email.text_body =~ "Your receipt is attached."
    end)
  end

  test "completes a delivery checkout with a geocoded address", %{conn: conn, order: order} do
    # Seed a delivery fulfillment option (the shared setup's pickup option
    # is unused in this test).
    delivery_option =
      generate(
        fulfillment_option(
          fulfillment_method: :delivery,
          rate_type: :fixed,
          base_price: "5.00"
        )
      )

    stub(Edenflowers.External.HereAPI.Mock, :geocode, fn _query ->
      {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
    end)

    stub(Edenflowers.External.HereAPI.Mock, :route_distance, fn _position -> {:ok, 3000} end)

    {:ok, view, _html} = live(conn, ~p"/checkout")

    view
    |> form("#checkout-form-1", %{
      "form" => %{
        "customer_name" => "Jane Doe",
        "customer_email" => "jane@example.com"
      }
    })
    |> render_submit()

    view
    |> form("#checkout-form-2", %{"form" => %{"gift" => "false"}})
    |> render_submit()

    # Pick delivery, then blur the address to trigger geocoding before submit.
    view
    |> element("#checkout-form-3a")
    |> render_change(%{"form" => %{"fulfillment_option_id" => delivery_option.id}})

    view
    |> element("#address-input-field")
    |> render_blur(%{"value" => "Stadsgatan 3, 65300 Vasa"})

    render_async(view, 500)

    fulfillment_date = Edenflowers.ShopTime.today() |> Date.add(7) |> Date.to_string()

    view
    |> element("#checkout-form-3b")
    |> render_submit(%{
      "form" => %{
        "delivery_address" => "Stadsgatan 3, 65300 Vasa",
        "recipient_phone_number" => "045 1234567",
        "delivery_instructions" => "Leave at back door",
        "fulfillment_date" => fulfillment_date
      }
    })

    assert render(view) =~ "Payment"

    view
    |> element("#checkout-form-4")
    |> render_submit()

    assert :ok =
             StripeHandler.handle_event(payment_intent_succeeded_event(order.id))

    finalized = Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])

    assert finalized.state == :placed
    assert finalized.payment_status == :paid
    assert finalized.fulfillment_method == :delivery
    assert finalized.delivery_address == "Stadsgatan 3, 65300 Vasa"
    assert finalized.geocoded_address == "Stadsgatan 3, 65300 Vasa"
    assert finalized.here_id == "here-id-123"
    assert finalized.position == "63.0951,21.6165"
    assert finalized.distance == 3000
    assert Decimal.eq?(finalized.fulfillment_fee, Decimal.new("5.00"))
    assert finalized.delivery_instructions == "Leave at back door"

    # The receipt and the shop's new-order email.
    assert %{success: 2, failure: 0} = Oban.drain_queue(queue: :default)

    assert_email_sent(fn email ->
      assert email.to == [{"", "jane@example.com"}]
      assert email.subject =~ "Your Eden Flowers order for"
      assert email.text_body =~ "Your receipt is attached."
      assert [%Swoosh.Attachment{content_type: "application/pdf"}] = email.attachments
    end)
  end

  # Mirrors the real webhook: the payment_intent's id and amount_received match
  # the order, so the handler's verification passes.
  defp payment_intent_succeeded_event(order_id) do
    order = Orders.get_order_by_id!(order_id, authorize?: false, load: [:grand_total])
    amount_received = Edenflowers.External.StripeAPI.to_stripe_amount(order.grand_total)

    %Stripe.Event{
      type: "payment_intent.succeeded",
      data: %{
        object: %{
          id: order.payment_intent_id,
          metadata: %{"order_id" => order.id},
          amount_received: amount_received
        }
      }
    }
  end
end
