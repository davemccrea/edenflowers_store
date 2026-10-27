defmodule EdenflowersWeb.Checkout.CheckoutDeliveryLiveTest do
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Mox
  import Phoenix.LiveViewTest

  alias Edenflowers.Orders

  setup :verify_on_exit!

  setup %{conn: conn} do
    product = generate(product())
    variant = generate(product_variant(product_id: product.id))

    # Insert pickup first to verify that delivery still wins the default and sort order.
    generate(fulfillment_option())

    delivery_option =
      generate(
        fulfillment_option(
          fulfillment_method: :delivery,
          rate_type: :fixed,
          base_price: "5.00",
          name: "Home delivery"
        )
      )

    step_3_order = generate(order(state: :delivery, customer_name: "Jane", customer_email: "jane@example.com"))
    Orders.add_line_item!(step_3_order.id, variant.id, 1, authorize?: false)

    mock_payment_intent = %{
      id: "pi_test_#{System.unique_integer([:positive])}",
      client_secret: "pi_test_secret"
    }

    stub(Edenflowers.External.StripeAPI.Mock, :create_payment_intent, fn _amount, _metadata, _customer ->
      {:ok, mock_payment_intent}
    end)

    stub(Edenflowers.External.StripeAPI.Mock, :retrieve_payment_intent, fn _order ->
      {:ok, mock_payment_intent}
    end)

    stub(Edenflowers.External.StripeAPI.Mock, :update_payment_intent, fn _payment_intent_id, _amount_cents ->
      {:ok, mock_payment_intent}
    end)

    conn = Plug.Test.init_test_session(conn, %{order_id: step_3_order.id})

    %{conn: conn, step_3_order: step_3_order, delivery_option: delivery_option}
  end

  describe "Step 3 for a subscribable product" do
    setup do
      %{
        variant: generate(product_variant(product_id: generate(product(subscribable: true, free_delivery: true)).id))
      }
    end

    test "subscribed to, shows how often and offers pickup too", %{conn: conn, variant: variant} do
      order = generate(order(state: :delivery, customer_name: "Jane", customer_email: "jane@example.com"))
      Orders.add_line_item!(order.id, variant.id, 1, %{interval_weeks: 2}, authorize?: false)
      conn = Plug.Test.init_test_session(conn, %{order_id: order.id})

      {:ok, view, _html} = live(conn, ~p"/checkout")

      assert has_element?(view, "#checkout-line-items [data-testid=line-item-interval]", "Every 2 weeks")
      assert has_element?(view, "label", "Fulfillment Option")
    end

    test "subscribed to, says what the card is charged and how often before paying",
         %{conn: conn, variant: variant, delivery_option: delivery_option} do
      first_delivery = Date.add(Edenflowers.ShopTime.today(), 5)

      order =
        generate(
          order(
            state: :payment,
            customer_name: "Jane",
            customer_email: "jane@example.com",
            fulfillment_option_id: delivery_option.id,
            fulfillment_date: first_delivery,
            quoted_fulfillment_fee: Decimal.new("5.00"),
            in_free_delivery_zone: false
          )
        )

      Orders.add_line_item!(order.id, variant.id, 1, %{interval_weeks: 2}, authorize?: false)
      stub(Edenflowers.External.StripeAPI.Mock, :create_customer, fn _params -> {:ok, %{id: "cus_jane"}} end)

      stub(Edenflowers.External.StripeAPI.Mock, :create_payment_intent_saving_card, fn _amount, _metadata, _customer ->
        {:ok, %{id: "pi_sub", client_secret: "pi_sub_secret"}}
      end)

      stub(Edenflowers.External.StripeAPI.Mock, :retrieve_payment_intent, fn _order ->
        {:ok, %{id: "pi_sub", client_secret: "pi_sub_secret", setup_future_usage: "off_session"}}
      end)

      {:ok, view, _html} = live(Plug.Test.init_test_session(conn, %{order_id: order.id}), ~p"/checkout")

      amount = Edenflowers.Format.currency(Decimal.add(variant.price, "5.00"), "en")
      second_delivery = Edenflowers.Format.weekday_date(Date.add(first_delivery, 14), "en")

      assert has_element?(
               view,
               "[data-testid='recurring-charge']",
               "Then #{amount} every 2 weeks from #{second_delivery}, charged 2 days before each delivery."
             )
    end

    test "subscribed to with a promotion, says the discount is for the first delivery",
         %{conn: conn, variant: variant} do
      order = generate(order(state: :delivery, customer_name: "Jane", customer_email: "jane@example.com"))
      Orders.add_line_item!(order.id, variant.id, 1, %{interval_weeks: 2}, authorize?: false)
      Orders.add_promotion_with_code!(order, generate(promotion()).code, authorize?: false)
      conn = Plug.Test.init_test_session(conn, %{order_id: order.id})

      {:ok, view, _html} = live(conn, ~p"/checkout")

      assert has_element?(view, "[data-testid='discount-section']")

      assert has_element?(
               view,
               "[data-testid='first-delivery-discount']",
               "The discount applies to your first delivery."
             )
    end

    test "subscribed to below a promotion's minimum, says nothing about the discount",
         %{conn: conn, variant: variant} do
      order =
        generate(
          order(
            state: :delivery,
            customer_name: "Jane",
            customer_email: "jane@example.com",
            promotion_id: generate(promotion()).id,
            promotion_minimum_cart_total: Decimal.new("1000")
          )
        )

      Orders.add_line_item!(order.id, variant.id, 1, %{interval_weeks: 2}, authorize?: false)
      conn = Plug.Test.init_test_session(conn, %{order_id: order.id})

      {:ok, view, _html} = live(conn, ~p"/checkout")

      refute has_element?(view, "[data-testid='first-delivery-discount']")
    end

    test "bought once with a promotion, says nothing about the first delivery", %{conn: conn, variant: variant} do
      order = generate(order(state: :delivery, customer_name: "Jane", customer_email: "jane@example.com"))
      Orders.add_line_item!(order.id, variant.id, 1, authorize?: false)
      Orders.add_promotion_with_code!(order, generate(promotion()).code, authorize?: false)
      conn = Plug.Test.init_test_session(conn, %{order_id: order.id})

      {:ok, view, _html} = live(conn, ~p"/checkout")

      assert has_element?(view, "[data-testid='discount-section']")
      refute has_element?(view, "[data-testid='first-delivery-discount']")
    end

    test "bought once, can be picked up", %{conn: conn, variant: variant} do
      order = generate(order(state: :delivery, customer_name: "Jane", customer_email: "jane@example.com"))
      Orders.add_line_item!(order.id, variant.id, 1, authorize?: false)
      conn = Plug.Test.init_test_session(conn, %{order_id: order.id})

      {:ok, view, _html} = live(conn, ~p"/checkout")

      refute has_element?(view, "#checkout-line-items", "Subscription")
      assert has_element?(view, "label", "Fulfillment Option")
    end
  end

  describe "live calendar availability" do
    test "flags a selected date that closes without losing the customer's input", %{conn: conn} do
      date = Date.add(Edenflowers.ShopTime.today(), 7)
      admin = generate(admin_user())
      {:ok, view, _html} = live(conn, ~p"/checkout")
      render_click(view, "select-date", %{"date" => Date.to_string(date)})

      view
      |> element("#checkout-form-3b")
      |> render_change(%{
        "form" => %{"fulfillment_date" => Date.to_string(date), "contact_phone_number" => "040 1234567"}
      })

      calendar = Edenflowers.Fulfillment.get_shop_calendar!()
      calendar = Edenflowers.Fulfillment.toggle_date!(calendar, date, actor: admin)

      assert has_element?(view, "[data-testid=fulfillment-date-unavailable]", "This date is no longer available")
      assert has_element?(view, ~s|input[name="form[fulfillment_date]"][value="#{date}"]|)
      assert has_element?(view, ~s|input[name="form[contact_phone_number]"][value="040 1234567"]|)

      assert has_element?(
               view,
               ~s|#calendar button[phx-value-date="#{date}"][aria-pressed="true"][aria-disabled="true"]|
             )

      Edenflowers.Fulfillment.toggle_date!(calendar, date, actor: admin)

      refute has_element?(view, "[data-testid=fulfillment-date-unavailable]")
      assert has_element?(view, ~s|input[name="form[fulfillment_date]"][value="#{date}"]|)
    end

    test "warns on payment without changing the order, and lets the customer edit the date", %{conn: conn} do
      date = Date.add(Edenflowers.ShopTime.today(), 7)
      order = order_in_payment(fulfillment_method: :pickup, fulfillment_date: date)
      admin = generate(admin_user())
      conn = Plug.Test.init_test_session(conn, %{order_id: order.id})
      {:ok, view, _html} = live(conn, ~p"/checkout")

      calendar = Edenflowers.Fulfillment.get_shop_calendar!()
      Edenflowers.Fulfillment.toggle_date!(calendar, date, actor: admin)

      assert has_element?(view, "[data-testid=fulfillment-date-unavailable]", "This date is no longer available")
      assert has_element?(view, "#checkout-form-4")
      saved = Orders.get_order_by_id!(order.id, authorize?: false)
      assert saved.state == :payment
      assert saved.fulfillment_date == date
      assert saved.payment_intent_id == order.payment_intent_id
      refute_push_event(view, "stripe:process_payment", %{})

      view |> element("[data-testid=fulfillment-date-unavailable] button", "Edit") |> render_click()

      assert_patch(view, ~p"/checkout?step=delivery")
      assert has_element?(view, ~s|#calendar button[phx-value-date="#{date}"][aria-disabled="true"]|)
      assert Orders.get_order_by_id!(order.id, authorize?: false).state == :delivery
    end

    test "an open checkout sees dates close and reopen without a reload", %{conn: conn} do
      date = Date.add(Edenflowers.ShopTime.today(), 1)
      admin = generate(admin_user())
      {:ok, view, _html} = live(conn, ~p"/checkout")
      selector = ~s|#calendar button[phx-value-date="#{date}"]|
      refute has_element?(view, selector <> ~s|[aria-disabled="true"]|)

      calendar = Edenflowers.Fulfillment.get_shop_calendar!()
      calendar = Edenflowers.Fulfillment.toggle_date!(calendar, date, actor: admin)

      assert has_element?(view, selector <> ~s|[aria-disabled="true"]|)

      Edenflowers.Fulfillment.toggle_date!(calendar, date, actor: admin)

      assert has_element?(view, selector)
      refute has_element?(view, selector <> ~s|[aria-disabled="true"]|)
    end
  end

  describe "Step 3: Delivery Information" do
    test "fresh order at step 3 defaults the radio to home delivery", %{
      conn: conn,
      step_3_order: step_3_order,
      delivery_option: delivery_option
    } do
      {:ok, _view, html} = live(conn, ~p"/checkout")

      pickup_option =
        Edenflowers.Fulfillment.list_options!()
        |> Enum.find(&(&1.fulfillment_method == :pickup))

      assert html =~ ~s(value="#{delivery_option.id}" checked)
      refute html =~ ~s(value="#{pickup_option.id}" checked)

      reloaded = Orders.get_order_for_checkout!(step_3_order.id, actor: nil)
      assert reloaded.fulfillment_option_id == delivery_option.id
      assert reloaded.fulfillment_method == :delivery
    end

    test "existing pickup choice is preserved on revisit", %{
      conn: conn,
      step_3_order: step_3_order,
      delivery_option: delivery_option
    } do
      pickup_option =
        Edenflowers.Fulfillment.list_options!()
        |> Enum.find(&(&1.fulfillment_method == :pickup))

      Orders.update_fulfillment_option!(step_3_order, pickup_option.id, actor: nil)

      {:ok, _view, html} = live(conn, ~p"/checkout")

      assert html =~ ~s(value="#{pickup_option.id}" checked)
      refute html =~ ~s(value="#{delivery_option.id}" checked)

      reloaded = Orders.get_order_for_checkout!(step_3_order.id, actor: nil)
      assert reloaded.fulfillment_option_id == pickup_option.id
    end

    test "submitting step 3 without changing the radio persists the delivery option", %{
      conn: conn,
      step_3_order: step_3_order,
      delivery_option: delivery_option
    } do
      stub(Edenflowers.External.HereAPI.Mock, :geocode, fn _query ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      stub(Edenflowers.External.HereAPI.Mock, :route_distance, fn _position -> {:ok, 3000} end)

      {:ok, view, _html} = live(conn, ~p"/checkout")

      view
      |> element("#address-input-field")
      |> render_blur(%{"value" => "Stadsgatan 3, 65300 Vasa"})

      render_async(view, 500)

      view
      |> element("#checkout-form-3b")
      |> render_submit(%{
        "form" => %{
          "delivery_address" => "Stadsgatan 3, 65300 Vasa",
          "contact_phone_number" => "045 1234567",
          "fulfillment_date" => Edenflowers.ShopTime.today() |> Date.add(7) |> Date.to_string()
        }
      })

      reloaded = Orders.get_order_for_checkout!(step_3_order.id, actor: nil)
      assert reloaded.fulfillment_option_id == delivery_option.id
      assert reloaded.fulfillment_method == :delivery
      assert reloaded.state == :payment
      assert_push_event(view, "focus-element", %{id: "checkout-section-payment", stepTop: true})
    end

    test "gives Stripe the buyer's phone number, but never a gift recipient's", %{
      conn: conn,
      step_3_order: step_3_order
    } do
      stub(Edenflowers.External.HereAPI.Mock, :geocode, fn _query ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      stub(Edenflowers.External.HereAPI.Mock, :route_distance, fn _position -> {:ok, 3000} end)

      submit_delivery = fn phone_number ->
        {:ok, view, _html} = live(conn, ~p"/checkout")
        view |> element("#address-input-field") |> render_blur(%{"value" => "Stadsgatan 3, 65300 Vasa"})
        render_async(view, 500)

        view
        |> element("#checkout-form-3b")
        |> render_submit(%{
          "form" => %{
            "delivery_address" => "Stadsgatan 3, 65300 Vasa",
            "contact_phone_number" => phone_number,
            "fulfillment_date" => Edenflowers.ShopTime.today() |> Date.add(7) |> Date.to_string()
          }
        })

        view
      end

      view = submit_delivery.("045 1234567")
      assert has_element?(view, ~s|#checkout-form-4[data-billing-phone="+358451234567"]|)

      step_3_order.id
      |> Orders.get_order_for_checkout!(actor: nil)
      |> Orders.return_to_delivery!(actor: nil)
      |> Orders.set_gift!(true, actor: nil)

      view = submit_delivery.("040 7654321")
      assert has_element?(view, ~s|#checkout-form-4[data-billing-phone="+358451234567"]|)
    end

    test "shows the customer's own number for themselves, and an empty field for a gift recipient", %{
      conn: conn,
      step_3_order: step_3_order
    } do
      step_3_order
      |> Ash.Changeset.for_update(:submit_delivery, %{
        fulfillment_date: Edenflowers.ShopTime.today() |> Date.add(7),
        delivery_address: "Stadsgatan 3, 65300 Vasa",
        contact_phone_number: "045 1234567"
      })
      |> Ash.Changeset.force_change_attributes(geocoded_address: "Stadsgatan 3, 65300 Vasa", distance: 3000)
      |> Ash.update!(authorize?: false)
      |> Orders.return_to_delivery!(actor: nil)

      {:ok, view, _html} = live(conn, ~p"/checkout")
      assert has_element?(view, ~s|input[name="form[contact_phone_number]"][value="045 1234567"]|)

      step_3_order.id
      |> Orders.get_order_for_checkout!(actor: nil)
      |> Orders.set_gift!(true, actor: nil)

      {:ok, view, _html} = live(conn, ~p"/checkout")
      refute has_element?(view, ~s|input[name="form[contact_phone_number]"][value]|)
    end

    # Closed days are only aria-disabled, so a click on one still arrives.
    test "picking a closed date keeps the form as it was", %{conn: conn} do
      closed = Edenflowers.ShopTime.today() |> Date.add(7)
      shop_calendar(disabled_dates: [closed])
      {:ok, view, _html} = live(conn, ~p"/checkout")

      render_click(view, "select-date", %{"date" => Date.to_string(closed)})

      assert has_element?(view, ~s|input[name="form[fulfillment_date]"]|)
      refute has_element?(view, ~s|input[name="form[fulfillment_date]"][value="#{closed}"]|)
    end
  end
end
