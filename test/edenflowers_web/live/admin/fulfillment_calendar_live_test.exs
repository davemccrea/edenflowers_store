defmodule EdenflowersWeb.Admin.FulfillmentCalendarLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Store.FulfillmentOption
  alias Edenflowers.Weekday

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

  describe "scope" do
    test "defaults to :all and switches when a chip is clicked", %{conn: conn, delivery: delivery} do
      {:ok, view, html} = live(conn, ~p"/admin/fulfillment-calendar")

      assert html =~ "All options"
      assert html =~ "Delivery"
      assert html =~ "Pickup"

      view
      |> element(~s|button[phx-value-scope="#{delivery.id}"]|, "Delivery")
      |> render_click()

      assert render(view) =~ "Delivery"
    end
  end

  describe "rendered styling" do
    # Guardrail: closed cells get the strike on ::after (so ::before is free for
    # the override corner); the legend swatch gets it on ::before. Both reference
    # the same underlying CSS rule in app.css, so drift in the visual is
    # impossible at the CSS layer — but this catches accidental removal of the
    # utility class from either element.
    test "closed cells and the legend swatch both render the diagonal-strike utility", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/fulfillment-calendar")

      # Sundays are closed for the delivery option set up in `setup`, so any
      # rendered Sunday in the current month carries the closed strike.
      assert html =~ "calendar-strike-after"
      assert html =~ "calendar-strike-before"
    end
  end

  describe "weekday toggle" do
    test "disables the weekday across every option when scope is :all", %{
      conn: conn,
      delivery: delivery,
      pickup: pickup
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillment-calendar")

      view
      |> element(~s|button[phx-click="weekday-click"][phx-value-weekday="monday"]|)
      |> render_click()

      drain(view)

      reloaded_delivery = FulfillmentOption.get_by_id!(delivery.id, authorize?: false)
      reloaded_pickup = FulfillmentOption.get_by_id!(pickup.id, authorize?: false)

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
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillment-calendar")

      view
      |> element(~s|button[phx-click="weekday-click"][phx-value-weekday="saturday"]|)
      |> render_click()

      drain(view)

      reloaded_delivery = FulfillmentOption.get_by_id!(delivery.id, authorize?: false)
      reloaded_pickup = FulfillmentOption.get_by_id!(pickup.id, authorize?: false)

      refute :saturday in reloaded_delivery.available_days
      refute :saturday in reloaded_pickup.available_days
    end

    test "toggling a weekday updates only the scoped option", %{
      conn: conn,
      delivery: delivery,
      pickup: pickup
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillment-calendar")

      view
      |> element(~s|button[phx-value-scope="#{delivery.id}"]|, "Delivery")
      |> render_click()

      view
      |> element(~s|button[phx-click="weekday-click"][phx-value-weekday="monday"]|)
      |> render_click()

      drain(view)

      reloaded_delivery = FulfillmentOption.get_by_id!(delivery.id, authorize?: false)
      reloaded_pickup = FulfillmentOption.get_by_id!(pickup.id, authorize?: false)

      refute :monday in reloaded_delivery.available_days
      assert :monday in reloaded_pickup.available_days
    end
  end

  describe "date toggle" do
    test "clicking an open future date adds it to disabled_dates for the scoped option", %{
      conn: conn,
      delivery: delivery
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillment-calendar")

      view
      |> element(~s|button[phx-value-scope="#{delivery.id}"]|, "Delivery")
      |> render_click()

      future = next_weekday(:monday)

      view
      |> element(~s|button[phx-click="select"][phx-value-date="#{Date.to_iso8601(future)}"]|)
      |> render_click()

      drain(view)

      reloaded = FulfillmentOption.get_by_id!(delivery.id, authorize?: false)
      assert future in reloaded.disabled_dates
    end
  end

  describe "week toggle" do
    test "clicking the week-toggle button closes every open cell in that week for the scoped option", %{
      conn: conn,
      delivery: delivery
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillment-calendar")

      view
      |> element(~s|button[phx-value-scope="#{delivery.id}"]|, "Delivery")
      |> render_click()

      # Pick a week payload whose dates are all in the future, so the click
      # actually has something to do.
      html = render(view)
      today = "Europe/Helsinki" |> DateTime.now!() |> DateTime.to_date()

      week_payload =
        Regex.scan(~r/phx-click="week-click" phx-value-week="([^"]+)"/, html)
        |> Enum.map(fn [_, payload] -> payload end)
        |> Enum.find(fn payload ->
          dates = payload |> String.split(",") |> Enum.map(&Date.from_iso8601!/1)
          Enum.all?(dates, &(Date.compare(&1, today) != :lt))
        end)

      assert week_payload, "expected at least one future week button in the rendered month"

      view
      |> element(~s|button[phx-click="week-click"][phx-value-week="#{week_payload}"]|)
      |> render_click()

      drain(view)

      reloaded = FulfillmentOption.get_by_id!(delivery.id, authorize?: false)

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
        FulfillmentOption.update_calendar(
          delivery,
          %{
            available_days: [:monday],
            enabled_dates: [~D[2026-12-25]],
            disabled_dates: [~D[2026-12-26]]
          },
          authorize?: false
        )

      {:ok, view, _html} = live(conn, ~p"/admin/fulfillment-calendar")

      view
      |> element(~s|button[phx-click="set-scope"][phx-value-scope="#{delivery.id}"]|)
      |> render_click()

      view
      |> element(~s|button[phx-click="reset-calendar"]|)
      |> render_click()

      drain(view)

      reloaded = FulfillmentOption.get_by_id!(delivery.id, authorize?: false)

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
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillment-calendar")

      view
      |> element(~s|button[phx-click="reset-calendar"]|)
      |> render_click()

      drain(view)

      reloaded_delivery = FulfillmentOption.get_by_id!(delivery.id, authorize?: false)
      reloaded_pickup = FulfillmentOption.get_by_id!(pickup.id, authorize?: false)

      for option <- [reloaded_delivery, reloaded_pickup] do
        assert :sunday in option.available_days
        assert option.enabled_dates == []
        assert option.disabled_dates == []
      end
    end

    test "renders a data-confirm attribute on the reset button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/fulfillment-calendar")
      assert html =~ "Are you sure you want to reset the calendar?"
    end
  end

  describe "redirects" do
    test "redirects unauthenticated users to /sign-in" do
      conn = Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{})

      assert {:error, {:redirect, %{to: to, flash: %{"error" => _}}}} =
               live(conn, ~p"/admin/fulfillment-calendar")

      assert to == "/sign-in?return_to=%2Fadmin%2Ffulfillment-calendar"
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
               live(conn, ~p"/admin/fulfillment-calendar")

      assert to == "/sign-in?return_to=%2Fadmin%2Ffulfillment-calendar"
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

  # seed_generator skips the GenerateTokenChange that normal sign-in would
  # run, so we mint a token by hand and stash it in __metadata__ where
  # store_in_session/2 expects to find it.
  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end
