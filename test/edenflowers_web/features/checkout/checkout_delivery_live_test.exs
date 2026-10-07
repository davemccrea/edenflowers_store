defmodule EdenflowersWeb.Checkout.CheckoutDeliveryLiveTest do
  use EdenflowersWeb.ConnCase, async: true

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

    stub(Edenflowers.External.StripeAPI.Mock, :create_payment_intent, fn _amount, _metadata ->
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
          "recipient_phone_number" => "045 1234567",
          "fulfillment_date" => Date.utc_today() |> Date.add(7) |> Date.to_string()
        }
      })

      reloaded = Orders.get_order_for_checkout!(step_3_order.id, actor: nil)
      assert reloaded.fulfillment_option_id == delivery_option.id
      assert reloaded.fulfillment_method == :delivery
      assert reloaded.state == :payment
    end

    test "gives Stripe the buyer's phone number, but never a gift recipient's", %{
      conn: conn,
      step_3_order: step_3_order
    } do
      stub(Edenflowers.External.HereAPI.Mock, :geocode, fn _query ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      stub(Edenflowers.External.HereAPI.Mock, :route_distance, fn _position -> {:ok, 3000} end)

      submit_delivery = fn ->
        {:ok, view, _html} = live(conn, ~p"/checkout")
        view |> element("#address-input-field") |> render_blur(%{"value" => "Stadsgatan 3, 65300 Vasa"})
        render_async(view, 500)

        view
        |> element("#checkout-form-3b")
        |> render_submit(%{
          "form" => %{
            "delivery_address" => "Stadsgatan 3, 65300 Vasa",
            "recipient_phone_number" => "045 1234567",
            "fulfillment_date" => Date.utc_today() |> Date.add(7) |> Date.to_string()
          }
        })

        view
      end

      view = submit_delivery.()
      assert has_element?(view, ~s|#checkout-form-4[data-billing-phone="+358451234567"]|)

      step_3_order.id
      |> Orders.get_order_for_checkout!(actor: nil)
      |> Orders.return_to_delivery!(actor: nil)
      |> Orders.set_gift!(true, actor: nil)

      view = submit_delivery.()
      assert has_element?(view, "#checkout-form-4")
      refute has_element?(view, "#checkout-form-4[data-billing-phone]")
    end

    test "formats the phone number every time the customer tabs out of it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkout")

      phone_input = ~s|#checkout-form-3b input[name="form[recipient_phone_number]"]|

      for typed <- ["0451505141", "+358 45 150 5141"] do
        view |> element("#checkout-form-3b") |> render_change(%{"form" => %{"recipient_phone_number" => typed}})
        assert has_element?(view, ~s|#{phone_input}[value="#{typed}"]|)

        view |> element(phone_input) |> render_blur(%{"value" => typed})
        assert has_element?(view, ~s|#{phone_input}[value="045 1505141"]|)
      end
    end

    test "delivery option renders before pickup regardless of insertion order", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/checkout")

      options = Edenflowers.Fulfillment.list_options!()
      delivery_id = Enum.find(options, &(&1.fulfillment_method == :delivery)).id
      pickup_id = Enum.find(options, &(&1.fulfillment_method == :pickup)).id

      {delivery_pos, _} = :binary.match(html, delivery_id)
      {pickup_pos, _} = :binary.match(html, pickup_id)

      assert delivery_pos < pickup_pos
    end

    test "switching fulfillment option clears the previously selected date", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkout")

      pickup_option =
        Edenflowers.Fulfillment.list_options!()
        |> Enum.find(&(&1.fulfillment_method == :pickup))

      # User picks a date on the delivery calendar. The checkout LiveView
      # stores that date in the form params via the `:date_selected` message.
      selected_date = Date.utc_today() |> Date.add(7) |> Date.to_string()
      send(view.pid, {:date_selected, selected_date})

      assert render(view) =~ ~s(value="#{selected_date}")

      # User then switches to a different fulfillment option. The new option
      # has its own calendar, so the date that was valid for delivery may not
      # be valid for pickup and must be cleared from the form.
      view
      |> element("#checkout-form-3a")
      |> render_change(%{"form" => %{"fulfillment_option_id" => pickup_option.id}})

      refute render(view) =~ ~s(value="#{selected_date}")
    end
  end
end
