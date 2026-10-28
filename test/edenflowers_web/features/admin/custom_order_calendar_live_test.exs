defmodule EdenflowersWeb.Admin.CustomOrderCalendarLiveTest do
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest

  setup :log_in_admin

  describe "placing a custom order" do
    test "warns about a closed day without refusing it", %{conn: conn} do
      pickup = generate(fulfillment_option(name: "Pickup at the shop", base_price: "0.00"))
      tomorrow = Date.add(Edenflowers.ShopTime.today(), 1)

      shop_calendar(available_days: [])

      {:ok, view, _html} = live(conn, ~p"/admin/orders/new")

      view
      |> form("#order-form",
        form: %{fulfillment_option_id: pickup.id, fulfillment_date: Date.to_iso8601(tomorrow)}
      )
      |> render_change()

      assert has_element?(view, "#date-warning", "normally closed")
    end
  end
end
