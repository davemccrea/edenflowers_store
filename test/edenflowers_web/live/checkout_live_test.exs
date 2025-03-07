defmodule EdenflowersWeb.CheckoutLiveTest do
  use EdenflowersWeb.ConnCase

  import Phoenix.LiveViewTest
  import Edenflowers.Fixtures

  setup %{conn: conn} do
    tax_rate = fixture(:tax_rate)

    fulfillment_option_1 =
      fixture(:fulfillment_option, %{
        name: "In store pickup",
        fulfillment_method: :pickup,
        rate_type: :fixed,
        base_price: "0.00",
        tax_rate_id: tax_rate.id
      })

    fulfillment_option_2 =
      fixture(:fulfillment_option, %{
        name: "Home delivery",
        fulfillment_method: :delivery,
        rate_type: :dynamic,
        minimum_cart_total: 0,
        base_price: "3.00",
        price_per_km: "1.50",
        free_dist_km: 5,
        max_dist_km: 20,
        tax_rate_id: tax_rate.id
      })

    {:ok, conn: conn, fulfillment_option_1: fulfillment_option_1, fulfillment_option_2: fulfillment_option_2}
  end

  test "delivery fields show when fulfillment_method is :delivery", %{
    conn: conn,
    fulfillment_option_2: fulfillment_option_2
  } do
    {:ok, view, _html} = live(conn, ~p"/checkout")

    assert has_element?(view, "#delivery-fields.hidden")

    view
    |> element("#checkout-step-1")
    |> render_change(%{"form" => %{"fulfillment_option_id" => fulfillment_option_2.id}})

    refute has_element?(view, "#delivery-fields.hidden")
  end

  test "no fields required to progress to step 2", %{conn: conn, fulfillment_option_1: fulfillment_option_1} do
    {:ok, view, _html} = live(conn, ~p"/checkout")

    assert has_element?(view, "#checkout-step-1")

    html =
      view
      |> element("#checkout-step-1")
      |> render_submit(%{
        "form" => %{
          "fulfillment_option_id" => fulfillment_option_1.id,
          "recipient_phone_number" => "0451505141"
        }
      })

    assert html =~ "id=\"checkout-step-2\""
  end

  test "displays error if delivery_address is empty when fulfillment_option method is delivery", %{
    conn: conn,
    fulfillment_option_2: fulfillment_option_2
  } do
    {:ok, view, html} = live(conn, ~p"/checkout")

    assert has_element?(view, "#checkout-step-1")
    refute html =~ "Address is required"

    html =
      view
      |> element("#checkout-step-1")
      |> render_submit(%{
        "form" => %{
          "fulfillment_option_id" => fulfillment_option_2.id,
          "delivery_address" => ""
        }
      })

    assert html =~ "Address is required"
  end

  test "form progresses to step 2 if address ok", %{conn: conn, fulfillment_option_2: fulfillment_option_2} do
    {:ok, view, _html} = live(conn, ~p"/checkout")

    assert has_element?(view, "#checkout-step-1")

    html =
      view
      |> element("#checkout-step-1")
      |> render_submit(%{
        "form" => %{
          "fulfillment_option_id" => fulfillment_option_2.id,
          "recipient_phone_number" => "0451505141",
          "delivery_address" => "Stadsgatan 3, 65300 Vasa"
        }
      })

    assert html =~ "id=\"checkout-step-2\""
  end

  # test "displays error if address is outside delivery zone", %{
  #   conn: conn,
  #   fulfillment_option_2: fulfillment_option_2
  # } do
  #   conn = get(conn, ~p"/checkout")
  #   {:ok, view, html} = live(conn)

  #   assert view |> element("#checkout-step-1") |> has_element?()

  #   html =
  #     view
  #     |> form("#checkout-step-1", %{
  #       "form" => %{
  #         "fulfillment_option_id" => fulfillment_option_2.id,
  #         "delivery_address" => "Södra Lappfjärdsvägen 45, 64300 Kristinestad"
  #       }
  #     })
  #     |> render_submit()

  #   assert html =~ "Out of delivery range"
  # end
end
