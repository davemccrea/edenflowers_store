defmodule EdenflowersWeb.CheckoutAddressLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator
  import Mox

  alias Edenflowers.Store.{LineItem, Order}

  setup :verify_on_exit!

  setup %{conn: conn} do
    product = generate(product())
    variant = generate(product_variant(%{product_id: product.id}))
    delivery_option = generate(fulfillment_option(fulfillment_method: :delivery, rate_type: :fixed, base_price: "5.00"))
    order = generate(order(step: 3, customer_name: "Jane", customer_email: "jane@example.com"))

    LineItem.add_item!(%{
      order_id: order.id,
      product_variant_id: variant.id,
      quantity: 1,
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

  describe "geocode lifecycle" do
    test "confirmed address shows check icon with distance and delivery cost", %{
      conn: conn,
      delivery_option: delivery_option
    } do
      stub_successful_geocode()

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Stadsgatan 3, 65300 Vasa")

      html = render_async(view)
      assert html =~ ~s(data-testid="input-confirmed")
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

      stub(Edenflowers.HereAPI.Mock, :get_distance, fn _position -> {:error, :out_of_delivery_range} end)

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Somewhere Far Away 1, 99999 Nowhere")

      html = render_async(view)
      assert html =~ "Outside delivery range"
      refute html =~ ~s(data-testid="input-confirmed")
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
  end

  describe "validation" do
    test "typing a partial address does not show a premature required error", %{
      conn: conn,
      delivery_option: delivery_option
    } do
      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      type_address(view, "Stadsgatan")

      refute render(view) =~ "Delivery address required"
    end

    test "clearing a confirmed address shows a required error", %{conn: conn, delivery_option: delivery_option} do
      stub_successful_geocode()

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Stadsgatan 3, 65300 Vasa")
      render_async(view)

      type_address(view, "")

      assert render(view) =~ "Delivery address required"
    end

    test "submitting step 3 without a confirmed address shows a required error", %{
      conn: conn,
      delivery_option: delivery_option
    } do
      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)

      view
      |> element("#checkout-form-3b")
      |> render_submit(%{"form" => %{"delivery_address" => ""}})

      assert render(view) =~ "Delivery address required"
    end
  end

  describe "confirmed state" do
    test "re-typing the address after confirmation clears the check icon", %{
      conn: conn,
      delivery_option: delivery_option
    } do
      stub_successful_geocode()

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Stadsgatan 3, 65300 Vasa")

      assert render_async(view) =~ ~s(data-testid="input-confirmed")

      type_address(view, "Stadsgatan 3, 65300 Vas")

      refute render(view) =~ ~s(data-testid="input-confirmed")
    end

    test "blurring the same confirmed address does not re-trigger geocoding", %{
      conn: conn,
      delivery_option: delivery_option
    } do
      expect(Edenflowers.HereAPI.Mock, :get_address, 1, fn _query ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      expect(Edenflowers.HereAPI.Mock, :get_distance, 1, fn _position -> {:ok, 3000} end)

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Stadsgatan 3, 65300 Vasa")
      render_async(view)

      blur_address(view, "Stadsgatan 3, 65300 Vasa")
      render_async(view)
    end

    test "switching from delivery to pickup clears confirmed state and hides the address field", %{
      conn: conn,
      delivery_option: delivery_option
    } do
      pickup_option = generate(fulfillment_option(fulfillment_method: :pickup, rate_type: :fixed, base_price: "0.00"))
      stub_successful_geocode()

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Stadsgatan 3, 65300 Vasa")

      assert render_async(view) =~ ~s(data-testid="input-confirmed")

      select_delivery_option(view, pickup_option.id)

      html = render(view)
      refute html =~ ~s(data-testid="input-confirmed")
      refute html =~ "form_delivery_address"
    end

    test "switching from pickup back to delivery clears the address field", %{
      conn: conn,
      delivery_option: delivery_option
    } do
      pickup_option = generate(fulfillment_option(fulfillment_method: :pickup, rate_type: :fixed, base_price: "0.00"))
      stub_successful_geocode()

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Stadsgatan 3, 65300 Vasa")
      render_async(view)

      select_delivery_option(view, pickup_option.id)
      select_delivery_option(view, delivery_option.id)

      html = render(view)
      refute html =~ "Stadsgatan 3, 65300 Vasa"
      refute html =~ ~s(data-testid="input-confirmed")
    end

    test "reloading the page with a persisted geocode shows the check icon without calling the API", %{
      conn: conn,
      order: order,
      delivery_option: delivery_option
    } do
      expect(Edenflowers.HereAPI.Mock, :get_address, 0, fn _query -> :should_not_be_called end)

      seed_confirmed_address(order, delivery_option)

      conn = Plug.Test.init_test_session(conn, %{order_id: order.id})
      {:ok, _view, html} = live(conn, ~p"/checkout")

      assert html =~ ~s(data-testid="input-confirmed")
    end
  end

  describe "step 3 submit" do
    test "blur does not persist the geocode to the database", %{
      conn: conn,
      order: order,
      delivery_option: delivery_option
    } do
      stub_successful_geocode()

      {:ok, view, _html} = live(conn, ~p"/checkout")

      select_delivery_option(view, delivery_option.id)
      blur_address(view, "Stadsgatan 3, 65300 Vasa")
      render_async(view)

      reloaded = Order.get_for_checkout!(order.id, actor: nil)
      assert is_nil(reloaded.delivery_address)
      assert is_nil(reloaded.geocoded_address)
      assert is_nil(reloaded.fulfillment_amount)
    end

    test "submit persists every geocode field, the sibling form fields, and advances the step", %{
      conn: conn,
      order: order,
      delivery_option: delivery_option
    } do
      stub_successful_geocode()

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

      reloaded = Order.get_for_checkout!(order.id, actor: nil)
      assert reloaded.step == 4
      assert reloaded.delivery_address == "Stadsgatan 3, 65300 Vasa"
      assert reloaded.geocoded_address == "Stadsgatan 3, 65300 Vasa"
      assert reloaded.position == "63.0951,21.6165"
      assert reloaded.here_id == "here-id-123"
      assert reloaded.distance == 3000
      assert Decimal.eq?(reloaded.fulfillment_amount, Decimal.new("5.00"))
      assert reloaded.recipient_phone_number == "045 1234567"
      assert reloaded.delivery_instructions == "Leave at back door 99B"
      assert reloaded.fulfillment_date == Date.utc_today() |> Date.add(7)
    end
  end

  defp stub_successful_geocode do
    stub(Edenflowers.HereAPI.Mock, :get_address, fn _query ->
      {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
    end)

    stub(Edenflowers.HereAPI.Mock, :get_distance, fn _position -> {:ok, 3000} end)
  end

  defp select_delivery_option(view, option_id) do
    view
    |> element("#checkout-form-3a")
    |> render_change(%{"form" => %{"fulfillment_option_id" => option_id}})
  end

  defp blur_address(view, address) do
    view
    |> element("#address-input-field")
    |> render_blur(%{"value" => address})
  end

  defp type_address(view, value) do
    view
    |> element("#address-input-field")
    |> render_change(%{"delivery_address" => value})
  end

  defp seed_confirmed_address(order, delivery_option) do
    order
    |> Ash.Changeset.for_update(:update, %{}, authorize?: false)
    |> Ash.Changeset.force_change_attributes(%{
      fulfillment_option_id: delivery_option.id,
      fulfillment_method: delivery_option.fulfillment_method,
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
