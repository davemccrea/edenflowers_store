defmodule EdenflowersWeb.CheckoutAddressLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator
  import Mox

  alias Edenflowers.Store.LineItem

  setup :verify_on_exit!

  setup %{conn: conn} do
    product = generate(product())
    variant = generate(product_variant(%{product_id: product.id}))
    delivery_option = generate(fulfillment_option(fulfillment_method: :delivery, rate_type: :fixed, base_price: "5.00"))
    order = generate(order(step: 3, customer_name: "Jane", customer_email: "jane@example.com"))

    LineItem.add_item!(%{
      order_id: order.id,
      product_id: product.id,
      product_variant_id: variant.id,
      product_name: product.name,
      product_image_slug: variant.image_slug,
      quantity: 1,
      unit_price: variant.price,
      tax_rate: Decimal.new("0.24")
    })

    stub(Edenflowers.StripeAPI.Mock, :create_payment_intent, fn _order ->
      {:ok, %{id: "pi_test", client_secret: "pi_test_secret"}}
    end)

    stub(Edenflowers.StripeAPI.Mock, :retrieve_payment_intent, fn _order ->
      {:ok, %{id: "pi_test", client_secret: "pi_test_secret"}}
    end)

    conn = Plug.Test.init_test_session(conn, %{order_id: order.id})

    %{conn: conn, order: order, delivery_option: delivery_option}
  end

  describe "address lookup" do
    test "happy path: confirmed address shows check icon", %{conn: conn, delivery_option: delivery_option} do
      stub(Edenflowers.HereAPI.Mock, :get_address, fn _query ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      stub(Edenflowers.HereAPI.Mock, :get_distance, fn _position -> {:ok, 3000} end)

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Stadsgatan 3, 65300 Vasa")

      assert render_async(view) =~ ~s(data-testid="input-confirmed")
    end

    test "confirmed address shows distance and delivery cost", %{conn: conn, delivery_option: delivery_option} do
      stub(Edenflowers.HereAPI.Mock, :get_address, fn _query ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      stub(Edenflowers.HereAPI.Mock, :get_distance, fn _position -> {:ok, 3000} end)

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Stadsgatan 3, 65300 Vasa")

      html = render_async(view)
      assert html =~ ~s(data-testid="address-distance")
      assert html =~ "3.0 km"
      assert html =~ "5.00"
    end

    test "address not found shows field error", %{conn: conn, delivery_option: delivery_option} do
      stub(Edenflowers.HereAPI.Mock, :get_address, fn _query -> {:error, :address_not_found} end)

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Nonsense 999")

      html = render_async(view)
      assert html =~ "Address not found"
      refute html =~ ~s(data-testid="input-confirmed")
    end

    test "out of delivery range shows field error", %{conn: conn, delivery_option: delivery_option} do
      stub(Edenflowers.HereAPI.Mock, :get_address, fn _query ->
        {:ok, {"Somewhere Far Away 1, 99999 Nowhere", "70.0000,30.0000", "here-id-456"}}
      end)

      stub(Edenflowers.HereAPI.Mock, :get_distance, fn _position ->
        {:error, :out_of_delivery_range}
      end)

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Somewhere Far Away 1, 99999 Nowhere")

      html = render_async(view)
      assert html =~ "Outside delivery range"
      refute html =~ ~s(data-testid="input-confirmed")
    end

    test "typing a partial address does not show a premature validation error", %{conn: conn, delivery_option: delivery_option} do
      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)

      view
      |> element("#checkout-form-3b")
      |> render_change(%{"form" => %{"delivery_address" => "Stadsgatan"}})

      refute render(view) =~ "Please enter and confirm a delivery address"
    end

    test "blurring an empty address field does nothing", %{conn: conn, delivery_option: delivery_option} do
      expect(Edenflowers.HereAPI.Mock, :get_address, 0, fn _query -> :should_not_be_called end)

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "")

      html = render(view)
      refute html =~ ~s(data-testid="input-confirmed")
      refute html =~ ~s(data-testid="input-loading")
    end

    test "blurring the same already-confirmed address does not re-trigger geocoding",
         %{conn: conn, delivery_option: delivery_option} do
      expect(Edenflowers.HereAPI.Mock, :get_address, 1, fn _query ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      expect(Edenflowers.HereAPI.Mock, :get_distance, 1, fn _position -> {:ok, 3000} end)

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Stadsgatan 3, 65300 Vasa")
      render_async(view)

      # Second blur on the same confirmed address — Mox will fail if get_address is called again
      blur_address(view, "Stadsgatan 3, 65300 Vasa")
      render_async(view)
    end

    test "re-typing the address after confirmation clears the check icon",
         %{conn: conn, delivery_option: delivery_option} do
      stub(Edenflowers.HereAPI.Mock, :get_address, fn _query ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      stub(Edenflowers.HereAPI.Mock, :get_distance, fn _position -> {:ok, 3000} end)

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Stadsgatan 3, 65300 Vasa")

      assert render_async(view) =~ ~s(data-testid="input-confirmed")

      view
      |> element("#checkout-form-3b")
      |> render_change(%{"form" => %{"delivery_address" => "Stadsgatan 3, 65300 Vas"}})

      refute render(view) =~ ~s(data-testid="input-confirmed")
    end

    test "emptying a confirmed address clears the persisted geocode from the database",
         %{conn: conn, order: order, delivery_option: delivery_option} do
      stub(Edenflowers.HereAPI.Mock, :get_address, fn _query ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      stub(Edenflowers.HereAPI.Mock, :get_distance, fn _position -> {:ok, 3000} end)

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Stadsgatan 3, 65300 Vasa")
      render_async(view)

      view
      |> element("#checkout-form-3b")
      |> render_change(%{"form" => %{"delivery_address" => ""}})

      reloaded = Edenflowers.Store.Order.get_for_checkout!(order.id, actor: nil)
      assert is_nil(reloaded.delivery_address)
      assert is_nil(reloaded.geocoded_address)
      assert is_nil(reloaded.distance)
      assert is_nil(reloaded.fulfillment_amount)
    end

    test "changing fulfillment option clears confirmed address", %{conn: conn, delivery_option: delivery_option} do
      pickup_option = generate(fulfillment_option(fulfillment_method: :pickup, rate_type: :fixed, base_price: "0.00"))

      stub(Edenflowers.HereAPI.Mock, :get_address, fn _query ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      stub(Edenflowers.HereAPI.Mock, :get_distance, fn _position -> {:ok, 3000} end)

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Stadsgatan 3, 65300 Vasa")

      assert render_async(view) =~ ~s(data-testid="input-confirmed")

      select_delivery_option(view, pickup_option.id)

      refute render(view) =~ ~s(data-testid="input-confirmed")
      refute render(view) =~ "form_delivery_address"
    end

    test "switching from pickup back to delivery clears the address field",
         %{conn: conn, delivery_option: delivery_option} do
      pickup_option = generate(fulfillment_option(fulfillment_method: :pickup, rate_type: :fixed, base_price: "0.00"))

      stub(Edenflowers.HereAPI.Mock, :get_address, fn _query ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      stub(Edenflowers.HereAPI.Mock, :get_distance, fn _position -> {:ok, 3000} end)

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Stadsgatan 3, 65300 Vasa")
      render_async(view)

      select_delivery_option(view, pickup_option.id)
      select_delivery_option(view, delivery_option.id)

      refute render(view) =~ "Stadsgatan 3, 65300 Vasa"
      refute render(view) =~ ~s(data-testid="input-confirmed")
    end

    test "all geocode fields are persisted to the database after confirmation",
         %{conn: conn, order: order, delivery_option: delivery_option} do
      stub(Edenflowers.HereAPI.Mock, :get_address, fn _query ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      stub(Edenflowers.HereAPI.Mock, :get_distance, fn _position -> {:ok, 3000} end)

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Stadsgatan 3, 65300 Vasa")
      render_async(view)

      reloaded = Edenflowers.Store.Order.get_for_checkout!(order.id, actor: nil)
      assert reloaded.delivery_address == "Stadsgatan 3, 65300 Vasa"
      assert reloaded.geocoded_address == "Stadsgatan 3, 65300 Vasa"
      assert reloaded.position == "63.0951,21.6165"
      assert reloaded.here_id == "here-id-123"
      assert reloaded.distance == 3000
      assert Decimal.eq?(reloaded.fulfillment_amount, Decimal.new("5.00"))
    end

    test "submitting step 3 saves form fields to the database",
         %{conn: conn, order: order, delivery_option: delivery_option} do
      stub(Edenflowers.HereAPI.Mock, :get_address, fn _query ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      stub(Edenflowers.HereAPI.Mock, :get_distance, fn _position -> {:ok, 3000} end)

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Stadsgatan 3, 65300 Vasa")
      render_async(view)

      view
      |> element("#checkout-form-3b")
      |> render_submit(%{
        "form" => %{
          "delivery_address" => "Stadsgatan 3, 65300 Vasa",
          "recipient_phone_number" => "045 1234567",
          "delivery_instructions" => "Leave at back door 99B",
          "fulfillment_date" => Date.utc_today() |> Date.add(7) |> Date.to_string()
        }
      })

      reloaded = Edenflowers.Store.Order.get_for_checkout!(order.id, actor: nil)
      assert reloaded.step == 4
      assert reloaded.recipient_phone_number == "045 1234567"
      assert reloaded.delivery_instructions == "Leave at back door 99B"
      assert reloaded.fulfillment_date == Date.utc_today() |> Date.add(7)
      # Confirmed address survives the submit
      assert reloaded.delivery_address == "Stadsgatan 3, 65300 Vasa"
      assert reloaded.geocoded_address == "Stadsgatan 3, 65300 Vasa"
      assert reloaded.distance == 3000
    end

    test "submitting step 3 without a confirmed address shows a validation error",
         %{conn: conn, delivery_option: delivery_option} do
      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)

      view
      |> element("#checkout-form-3b")
      |> render_submit(%{"form" => %{"delivery_address" => ""}})

      assert render(view) =~ "Please enter and confirm a delivery address"
    end

    test "reloading the page with a previously confirmed address shows the check icon",
         %{conn: conn, order: order, delivery_option: delivery_option} do
      expect(Edenflowers.HereAPI.Mock, :get_address, 0, fn _query -> :should_not_be_called end)

      seed_confirmed_address(order, delivery_option)

      conn = Plug.Test.init_test_session(conn, %{order_id: order.id})
      {:ok, _view, html} = live(conn, ~p"/checkout")

      assert html =~ ~s(data-testid="input-confirmed")
    end

    test "navigating back to step 3 from step 4 shows the check icon for a confirmed address",
         %{conn: conn, order: order, delivery_option: delivery_option} do
      expect(Edenflowers.HereAPI.Mock, :get_address, 0, fn _query -> :should_not_be_called end)

      seed_confirmed_address(order, delivery_option)

      order
      |> Ash.Changeset.for_update(:update, %{}, authorize?: false)
      |> Ash.Changeset.force_change_attributes(%{step: 4})
      |> Ash.update!(authorize?: false)

      conn = Plug.Test.init_test_session(conn, %{order_id: order.id})
      {:ok, view, _html} = live(conn, ~p"/checkout")

      view |> element("[phx-click='edit_step_3']") |> render_click()

      assert render(view) =~ ~s(data-testid="input-confirmed")
    end

    test "advancing from step 2 to step 3 shows the check icon for a confirmed address",
         %{conn: conn, order: order, delivery_option: delivery_option} do
      expect(Edenflowers.HereAPI.Mock, :get_address, 0, fn _query -> :should_not_be_called end)

      seed_confirmed_address(order, delivery_option)

      # Roll back to step 2 so we can advance forward
      order
      |> Ash.Changeset.for_update(:update, %{}, authorize?: false)
      |> Ash.Changeset.force_change_attributes(%{step: 2})
      |> Ash.update!(authorize?: false)

      conn = Plug.Test.init_test_session(conn, %{order_id: order.id})
      {:ok, view, _html} = live(conn, ~p"/checkout")

      view |> element("#checkout-form-2") |> render_submit(%{"form" => %{}})

      assert render(view) =~ ~s(data-testid="input-confirmed")
    end
  end

  describe "address lookup does not affect other form fields" do
    setup %{conn: conn, delivery_option: delivery_option} do
      stub(Edenflowers.HereAPI.Mock, :get_address, fn _query ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      stub(Edenflowers.HereAPI.Mock, :get_distance, fn _position -> {:ok, 3000} end)

      {:ok, view, _html} = live(conn, ~p"/checkout")
      select_delivery_option(view, delivery_option.id)

      %{view: view}
    end

    test "delivery instructions are preserved after address confirmation", %{view: view} do
      view
      |> element("#checkout-form-3b")
      |> render_change(%{"form" => %{"delivery_address" => "Stadsgatan 3, 65300 Vasa", "delivery_instructions" => "Leave at back door 99B"}})

      blur_address(view, "Stadsgatan 3, 65300 Vasa")

      assert render_async(view) =~ "Leave at back door 99B"
    end

    test "phone number typed before address is preserved after address confirmation", %{view: view} do
      # Simulate typing phone first, then moving to the address field.
      # The last phx-change before blur only carries delivery_address — the
      # phone number is not re-sent, so it must survive from the earlier change.
      view
      |> element("#checkout-form-3b")
      |> render_change(%{"form" => %{"recipient_phone_number" => "045 1234567"}})

      view
      |> element("#checkout-form-3b")
      |> render_change(%{"form" => %{"delivery_address" => "Stadsgatan 3, 65300 Vasa"}})

      blur_address(view, "Stadsgatan 3, 65300 Vasa")

      assert render_async(view) =~ "045 1234567"
    end

    test "a failed geocode does not clear other fields", %{view: view} do
      stub(Edenflowers.HereAPI.Mock, :get_address, fn _query -> {:error, :address_not_found} end)

      view
      |> element("#checkout-form-3b")
      |> render_change(%{"form" => %{"recipient_phone_number" => "045 1234567", "delivery_instructions" => "Leave at back door 99B"}})

      blur_address(view, "Nonsense 999")
      html = render_async(view)

      assert html =~ "045 1234567"
      assert html =~ "Leave at back door 99B"
    end
  end

  defp select_delivery_option(view, option_id) do
    view
    |> element("#checkout-form-3a")
    |> render_change(%{"form" => %{"fulfillment_option_id" => option_id}})
  end

  defp blur_address(view, address) do
    view
    |> element("#form_delivery_address")
    |> render_blur(%{"value" => address})
  end

  defp seed_confirmed_address(order, delivery_option) do
    order
    |> Ash.Changeset.for_update(:update, %{}, authorize?: false)
    |> Ash.Changeset.force_change_attributes(%{
      fulfillment_option_id: delivery_option.id,
      delivery_address: "Stadsgatan 3, 65300 Vasa",
      geocoded_address: "Stadsgatan 3, 65300 Vasa",
      here_id: "here-id-123",
      position: "63.0951,21.6165",
      distance: 3000,
      fulfillment_amount: Decimal.new("5.00")
    })
    |> Ash.update!(authorize?: false)
  end
end
