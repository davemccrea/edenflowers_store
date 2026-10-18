defmodule EdenflowersWeb.Admin.FulfillmentsLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Weekday
  alias Edenflowers.ShopTime

  setup %{conn: conn} do
    tax_rate = generate(tax_rate())

    delivery = generate(fulfillment_option(tax_rate_id: tax_rate.id, fulfillment_method: :delivery, name: "Delivery"))
    pickup = generate(fulfillment_option(tax_rate_id: tax_rate.id, fulfillment_method: :pickup, name: "Pickup"))
    shop_calendar(available_days: [:monday, :tuesday, :wednesday, :thursday, :friday])

    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    %{conn: conn, admin: admin, delivery: delivery, pickup: pickup}
  end

  describe "options list" do
    test "links each option to its own page", %{conn: conn, delivery: delivery, pickup: pickup} do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments")
      render_async(view, 500)

      assert has_element?(view, ~s|tr a[href="/admin/fulfillments/#{delivery.id}"]|, "Delivery")
      assert has_element?(view, ~s|tr a[href="/admin/fulfillments/#{pickup.id}"]|, "Pickup")
    end

    test "lists options in their sort order, not by name", %{conn: conn} do
      generate(fulfillment_option(name: "Zeta", sort_key: -2))
      generate(fulfillment_option(name: "Alpha", sort_key: -1))
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments")

      html = render_async(view, 500)
      assert :binary.match(html, "Zeta") < :binary.match(html, "Alpha")
    end

    test "summarises each option's prices", %{conn: conn} do
      generate(
        fulfillment_option(
          fulfillment_method: :delivery,
          rate_type: :dynamic,
          name: "Home delivery",
          base_price: "3.00",
          price_per_km: "1.50",
          free_dist_km: 5,
          max_dist_km: 20
        )
      )

      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments")

      assert render_async(view, 500) =~ "€3.00 · €1.50/km · free within 5 km · up to 20 km"
    end

    test "an unknown option goes back to the list", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/fulfillments"}}} =
               live(conn, ~p"/admin/fulfillments/#{Ash.UUID.generate()}")
    end
  end

  describe "accessible state" do
    test "weekday toggles announce open and closed", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/fulfillments")

      assert html =~ ~s(aria-label="Toggle Monday, open")
      assert html =~ ~s(aria-label="Toggle Sunday, closed")
    end
  end

  describe "rendered styling" do
    # The strike lives on ::after so ::before stays free for the override corner.
    test "closed cells and the legend swatch both render the diagonal-strike utility", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments")

      # Weekends are closed in `setup`. Next month's Sundays are all still
      # ahead, whatever today is, so they render as closed rather than past.
      view |> element("#admin-fulfillment-calendar-next-month") |> render_click()

      assert has_element?(view, "button.calendar-strike-after")
      assert has_element?(view, "span.calendar-strike-after")
    end
  end

  describe "weekday toggle" do
    test "closes an open weekday", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments")

      view
      |> element(~s|button[phx-click="weekday-click"][phx-value-weekday="monday"]|)
      |> render_click()

      drain(view)

      refute :monday in Fulfillment.get_shop_calendar!().available_days
    end

    test "opens a closed weekday", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments")

      view
      |> element(~s|button[phx-click="weekday-click"][phx-value-weekday="saturday"]|)
      |> render_click()

      drain(view)

      assert :saturday in Fulfillment.get_shop_calendar!().available_days
    end
  end

  describe "date toggle" do
    test "clicking an open future date closes it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments")

      future = next_weekday(:monday)
      today = Edenflowers.ShopTime.today()

      if future.month != today.month do
        view
        |> element("#admin-fulfillment-calendar-next-month")
        |> render_click()
      end

      view
      |> element(~s|button[phx-click="select"][phx-value-date="#{Date.to_iso8601(future)}"]|)
      |> render_click()

      drain(view)

      assert future in Fulfillment.get_shop_calendar!().disabled_dates
    end
  end

  describe "week toggle" do
    test "clicking the week-toggle button closes every open cell in that week", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments")

      # Pick a week payload whose weekday dates are all strictly in the future,
      # so the click actually has something to disable. Navigate to next month
      # if no such week exists in the current view (e.g. running near month-end).
      today = Edenflowers.ShopTime.today()
      tomorrow = Date.add(today, 1)

      find_future_week = fn html ->
        Regex.scan(~r/phx-click="week-click" phx-value-week="([^"]+)"/, html)
        |> Enum.map(fn [_, payload] -> payload end)
        |> Enum.find(fn payload ->
          dates = payload |> String.split(",") |> Enum.map(&Date.from_iso8601!/1)
          weekdays = Enum.filter(dates, &(Date.day_of_week(&1) in 1..5))
          weekdays != [] and Enum.all?(weekdays, &(Date.compare(&1, tomorrow) != :lt))
        end)
      end

      week_payload =
        case find_future_week.(render(view)) do
          nil ->
            view |> element("#admin-fulfillment-calendar-next-month") |> render_click()
            find_future_week.(render(view))

          payload ->
            payload
        end

      assert week_payload, "expected at least one future week button in the rendered view"

      view
      |> element(~s|button[phx-click="week-click"][phx-value-week="#{week_payload}"]|)
      |> render_click()

      drain(view)

      # The shop is open Mon-Fri; clicking the week-toggle closes Mon-Fri of that week.
      week_dates = week_payload |> String.split(",") |> Enum.map(&Date.from_iso8601!/1)
      weekday_cells = Enum.filter(week_dates, &(Date.day_of_week(&1) in 1..5))
      assert Enum.all?(weekday_cells, &(&1 in Fulfillment.get_shop_calendar!().disabled_dates))
    end
  end

  describe "reset" do
    test "wipes overrides and reopens every weekday", %{conn: conn} do
      shop_calendar(enabled_dates: [Date.add(ShopTime.today(), 30)], disabled_dates: [Date.add(ShopTime.today(), 31)])
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments")

      assert has_element?(view, ~s|button[phx-click="reset-calendar"][data-confirm]|)

      view
      |> element(~s|button[phx-click="reset-calendar"]|)
      |> render_click()

      drain(view)

      calendar = Fulfillment.get_shop_calendar!()
      assert Enum.sort(calendar.available_days) == Enum.sort(Weekday.all())
      assert calendar.enabled_dates == []
      assert calendar.disabled_dates == []
    end
  end

  describe "same-day" do
    test "switching same-day off", %{conn: conn} do
      shop_calendar(same_day: true, order_deadline: ~T[14:00:00])
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments")
      assert has_element?(view, "#same-day-form input.toggle[type=checkbox]")
      refute has_element?(view, "#same-day-form fieldset.hidden input[type=time]")

      view |> form("#same-day-form", %{"same_day" => %{"same_day" => "false"}}) |> render_change()
      assert has_element?(view, "#same-day-form fieldset.hidden input[type=time]")

      view
      |> form("#same-day-form", %{"same_day" => %{"same_day" => "false"}})
      |> render_submit()

      assert render(view) =~ "Saved."
      refute Fulfillment.get_shop_calendar!().same_day
    end

    test "switching same-day on with a deadline", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments")

      view
      |> form("#same-day-form", %{"same_day" => %{"same_day" => "true", "order_deadline" => "12:00"}})
      |> render_submit()

      calendar = Fulfillment.get_shop_calendar!()
      assert {calendar.same_day, calendar.order_deadline} == {true, ~T[12:00:00]}
    end

    test "turning same-day on needs a deadline", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments")

      html =
        view
        |> form("#same-day-form", %{"same_day" => %{"same_day" => "true", "order_deadline" => ""}})
        |> render_submit()

      assert html =~ "is required"
      refute Fulfillment.get_shop_calendar!().same_day
    end
  end

  describe "prices" do
    setup do
      home_delivery =
        generate(fulfillment_option(fulfillment_method: :delivery, rate_type: :dynamic, name: "Home delivery"))

      %{home_delivery: home_delivery}
    end

    test "saving updates the option and the free-delivery distance on product pages", %{
      conn: conn,
      home_delivery: home_delivery
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments/#{home_delivery.id}")

      view
      |> form("#pricing-form", %{
        "pricing" => %{"base_price" => "6.00", "price_per_km" => "2.50", "free_dist_km" => "9", "max_dist_km" => "30"}
      })
      |> render_submit()

      assert render(view) =~ "Saved."
      assert_push_event(view, "admin-form-saved", %{id: "pricing-form"})

      saved = Fulfillment.get_option_by_id!(home_delivery.id, authorize?: false)
      assert Decimal.equal?(saved.base_price, "6.00")
      assert Decimal.equal?(saved.price_per_km, "2.50")
      assert {saved.free_dist_km, saved.max_dist_km} == {9, 30}

      product = generate(product(free_delivery: true, draft: false))
      generate(product_variant(product_id: product.id))
      {:ok, _view, html} = live(conn, ~p"/product/#{product.id}")
      assert html =~ "Free delivery within 9 km"
    end

    test "shows distance fields only for distance-priced options", %{
      conn: conn,
      home_delivery: home_delivery,
      pickup: pickup
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments/#{home_delivery.id}")
      assert has_element?(view, "#pricing-form input[name='pricing[free_dist_km]']")

      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments/#{pickup.id}")
      assert has_element?(view, "#pricing-form input[name='pricing[base_price]']")
      refute has_element?(view, "#pricing-form input[name='pricing[free_dist_km]']")
    end

    test "a free distance beyond the maximum shows an error and saves nothing", %{
      conn: conn,
      home_delivery: home_delivery
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments/#{home_delivery.id}")

      html =
        view
        |> form("#pricing-form", %{"pricing" => %{"free_dist_km" => "50", "max_dist_km" => "20"}})
        |> render_submit()

      refute html =~ "Saved."

      assert Fulfillment.get_option_by_id!(home_delivery.id, authorize?: false).free_dist_km ==
               home_delivery.free_dist_km
    end

    test "the option page has no calendar or same-day fields", %{conn: conn, pickup: pickup} do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments/#{pickup.id}")

      refute has_element?(view, "#admin-fulfillment-calendar")
      refute has_element?(view, "#pricing-form input[name='pricing[same_day]']")
    end
  end

  describe "redirects" do
    test "redirects unauthenticated users to /sign-in" do
      conn = Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{})

      assert {:error, {:redirect, %{to: to, flash: %{"error" => _}}}} =
               live(conn, ~p"/admin/fulfillments")

      assert to == "/sign-in?return_to=%2Fadmin%2Ffulfillments"
    end

    test "redirects non-admin authenticated users to /sign-in" do
      # A user that exists but isn't an admin should still get bounced.
      regular_user =
        Generator.admin_user(admin: false)
        |> Generator.generate()
        |> with_token()

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Test.init_test_session(%{})
        |> Helpers.store_in_session(regular_user)

      assert {:error, {:redirect, %{to: to, flash: %{"error" => _}}}} =
               live(conn, ~p"/admin/fulfillments")

      assert to == "/sign-in?return_to=%2Fadmin%2Ffulfillments"
    end
  end

  # The component sends results to the parent via send(self(), ...), which
  # land as handle_info messages. render_click only awaits the handle_event,
  # so we force a sync round-trip before asserting on persisted state.
  defp drain(view), do: _ = render(view)

  # Pick the next future date that lands on a given weekday.
  defp next_weekday(weekday_atom) do
    target = Weekday.to_integer(weekday_atom)
    today = Edenflowers.ShopTime.today()
    offset = Enum.find(1..21, &(Date.day_of_week(Date.add(today, &1)) == target))
    Date.add(today, offset)
  end
end
