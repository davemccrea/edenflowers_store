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
    conn = get(conn, ~p"/checkout")

    {:ok, view, _html} = live(conn)

    assert has_element?(view, "#delivery-fields.hidden")

    view
    |> form("#checkout-step-1")
    |> render_change(%{"form" => %{"fulfillment_option_id" => fulfillment_option_2.id}})

    refute has_element?(view, "#delivery-fields.hidden")
  end

  test "test", %{conn: conn, fulfillment_option_1: fulfillment_option_1} do
    conn = get(conn, ~p"/checkout")
    {:ok, view, _html} = live(conn)

    assert view |> element("#checkout-step-1") |> has_element?()

    html =
      view
      |> form("#checkout-step-1", %{
        "form" => %{
          "fulfillment_option_id" => fulfillment_option_1.id,
          "recipient_phone_number" => "0451505141"
        }
      })
      |> render_submit()

    assert html =~ "id=\"checkout-step-2\""
  end
end
