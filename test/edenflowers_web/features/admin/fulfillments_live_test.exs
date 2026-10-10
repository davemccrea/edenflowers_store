defmodule EdenflowersWeb.Admin.FulfillmentsLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Expressions.HelsinkiToday
  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Weekday

  setup %{conn: conn} do
    tax_rate = generate(tax_rate())

    delivery =
      generate(
        fulfillment_option(
          tax_rate_id: tax_rate.id,
          fulfillment_method: :delivery,
          name: "Delivery",
          available_days: [:monday, :tuesday, :wednesday, :thursday, :friday]
        )
      )

    pickup =
      generate(
        fulfillment_option(
          tax_rate_id: tax_rate.id,
          fulfillment_method: :pickup,
          name: "Pickup",
          available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
        )
      )

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

      assert has_element?(view, ~s|#fulfillment-options a[href="/admin/fulfillments/#{delivery.id}"]|, "Delivery")
      assert has_element?(view, ~s|#fulfillment-options a[href="/admin/fulfillments/#{pickup.id}"]|, "Pickup")
    end

    test "summarises each option's prices", %{conn: conn} do
      home_delivery =
        generate(
          fulfillment_option(
            fulfillment_method: :delivery,
            rate_type: :dynamic,
            name: "Home delivery",
            base_price: "3.00",
            price_per_km: "1.50",
            free_dist_km: 5,
            max_dist_km: 20,
            same_day: false
          )
        )

      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments")

      assert has_element?(
               view,
               ~s|a[href="/admin/fulfillments/#{home_delivery.id}"]|,
               "€3.00 · €1.50/km · free within 5 km · up to 20 km"
             )
    end

    test "an unknown option goes back to the list", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/fulfillments"}}} =
               live(conn, ~p"/admin/fulfillments/#{Ash.UUID.generate()}")
    end
  end

  describe "accessible state" do
    test "weekday toggles announce open, closed and mixed", %{conn: conn, delivery: delivery} do
      {:ok, _view, html} = live(conn, ~p"/admin/fulfillments")

      assert html =~ ~s(aria-label="Toggle Monday, open")
      assert html =~ ~s(aria-label="Toggle Saturday, options have different settings")

      {:ok, _view, html} = live(conn, ~p"/admin/fulfillments/#{delivery.id}")
      assert html =~ ~s(aria-label="Toggle Sunday, closed")
    end
  end

  describe "rendered styling" do
    # The strike lives on ::after so ::before stays free for the override corner.
    test "closed cells and the legend swatch both render the diagonal-strike utility", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments")

      # Sundays are closed for both options set up in `setup`. Next month's
      # Sundays are all still ahead, whatever today is, so they render as
      # closed rather than past.
      view |> element("#admin-fulfillment-calendar-next-month") |> render_click()

      assert has_element?(view, "button.calendar-strike-after")
      assert has_element?(view, "span.calendar-strike-after")
    end
  end

  describe "weekday toggle" do
    test "disables the weekday across every option when scope is :all", %{
      conn: conn,
      delivery: delivery,
      pickup: pickup
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments")

      view
      |> element(~s|button[phx-click="weekday-click"][phx-value-weekday="monday"]|)
      |> render_click()

      drain(view)

      reloaded_delivery = Fulfillment.get_option_by_id!(delivery.id, authorize?: false)
      reloaded_pickup = Fulfillment.get_option_by_id!(pickup.id, authorize?: false)

      refute :monday in reloaded_delivery.available_days
      refute :monday in reloaded_pickup.available_days
    end

    test "closes the weekday everywhere when options disagree and at least one has it on", %{
      conn: conn,
      delivery: delivery,
      pickup: pickup
    } do
      # Saturday: delivery=off, pickup=on. The smart toggle aggregates: any
      # option has Saturday on → click closes Saturday everywhere.
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments")

      view
      |> element(~s|button[phx-click="weekday-click"][phx-value-weekday="saturday"]|)
      |> render_click()

      drain(view)

      reloaded_delivery = Fulfillment.get_option_by_id!(delivery.id, authorize?: false)
      reloaded_pickup = Fulfillment.get_option_by_id!(pickup.id, authorize?: false)

      refute :saturday in reloaded_delivery.available_days
      refute :saturday in reloaded_pickup.available_days
    end

    test "toggling a weekday updates only the scoped option", %{
      conn: conn,
      delivery: delivery,
      pickup: pickup
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments/#{delivery.id}")

      view
      |> element(~s|button[phx-click="weekday-click"][phx-value-weekday="monday"]|)
      |> render_click()

      drain(view)

      reloaded_delivery = Fulfillment.get_option_by_id!(delivery.id, authorize?: false)
      reloaded_pickup = Fulfillment.get_option_by_id!(pickup.id, authorize?: false)

      refute :monday in reloaded_delivery.available_days
      assert :monday in reloaded_pickup.available_days
    end
  end

  describe "date toggle" do
    test "clicking an open future date adds it to disabled_dates for the scoped option", %{
      conn: conn,
      delivery: delivery
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments/#{delivery.id}")

      future = next_weekday(:monday)
      today = "Europe/Helsinki" |> DateTime.now!() |> DateTime.to_date()

      if future.month != today.month do
        view
        |> element("#admin-fulfillment-calendar-next-month")
        |> render_click()
      end

      view
      |> element(~s|button[phx-click="select"][phx-value-date="#{Date.to_iso8601(future)}"]|)
      |> render_click()

      drain(view)

      reloaded = Fulfillment.get_option_by_id!(delivery.id, authorize?: false)
      assert future in reloaded.disabled_dates
    end
  end

  describe "week toggle" do
    test "clicking the week-toggle button closes every open cell in that week for the scoped option", %{
      conn: conn,
      delivery: delivery
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments/#{delivery.id}")

      # Pick a week payload whose weekday dates are all strictly in the future,
      # so the click actually has something to disable. Navigate to next month
      # if no such week exists in the current view (e.g. running near month-end).
      today = "Europe/Helsinki" |> DateTime.now!() |> DateTime.to_date()
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

      reloaded = Fulfillment.get_option_by_id!(delivery.id, authorize?: false)

      # Delivery is open Mon-Fri; clicking the week-toggle closes Mon-Fri of that week.
      week_dates = week_payload |> String.split(",") |> Enum.map(&Date.from_iso8601!/1)
      weekday_cells = Enum.filter(week_dates, &(Date.day_of_week(&1) in 1..5))
      assert Enum.all?(weekday_cells, &(&1 in reloaded.disabled_dates))
    end
  end

  describe "reset" do
    test "wipes overrides and reopens every weekday for the scoped option", %{
      conn: conn,
      delivery: delivery
    } do
      # Seed delivery with an override and a non-default weekday rule.
      {:ok, _} =
        Fulfillment.update_calendar(
          delivery,
          %{
            available_days: [:monday],
            enabled_dates: [Date.add(HelsinkiToday.today(), 30)],
            disabled_dates: [Date.add(HelsinkiToday.today(), 31)]
          },
          authorize?: false
        )

      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments/#{delivery.id}")

      view
      |> element(~s|button[phx-click="reset-calendar"]|)
      |> render_click()

      drain(view)

      reloaded = Fulfillment.get_option_by_id!(delivery.id, authorize?: false)

      assert Enum.sort(reloaded.available_days) ==
               [:friday, :monday, :saturday, :sunday, :thursday, :tuesday, :wednesday]

      assert reloaded.enabled_dates == []
      assert reloaded.disabled_dates == []
    end

    test "resets every option when scope is :all", %{
      conn: conn,
      delivery: delivery,
      pickup: pickup
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments")

      view
      |> element(~s|button[phx-click="reset-calendar"]|)
      |> render_click()

      drain(view)

      reloaded_delivery = Fulfillment.get_option_by_id!(delivery.id, authorize?: false)
      reloaded_pickup = Fulfillment.get_option_by_id!(pickup.id, authorize?: false)

      for option <- [reloaded_delivery, reloaded_pickup] do
        assert :sunday in option.available_days
        assert option.enabled_dates == []
        assert option.disabled_dates == []
      end
    end

    test "renders a data-confirm attribute on the reset button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/fulfillments")
      assert html =~ "Reset every fulfillment option?"
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

      assert render(view) =~ "Prices saved."

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

      refute html =~ "Prices saved."

      assert Fulfillment.get_option_by_id!(home_delivery.id, authorize?: false).free_dist_km ==
               home_delivery.free_dist_km
    end

    test "same-day without a deadline shows an error", %{conn: conn, pickup: pickup} do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillments/#{pickup.id}")

      html =
        view
        |> form("#pricing-form", %{"pricing" => %{"same_day" => "true", "order_deadline" => ""}})
        |> render_submit()

      assert html =~ "is required"
      assert Fulfillment.get_option_by_id!(pickup.id, authorize?: false).order_deadline == pickup.order_deadline
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
    today = "Europe/Helsinki" |> DateTime.now!() |> DateTime.to_date()
    offset = Enum.find(1..21, &(Date.day_of_week(Date.add(today, &1)) == target))
    Date.add(today, offset)
  end
end
