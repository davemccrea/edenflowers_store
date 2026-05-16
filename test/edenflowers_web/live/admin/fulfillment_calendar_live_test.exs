defmodule EdenflowersWeb.Admin.FulfillmentCalendarLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Store.FulfillmentOption

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
    # Guardrail: the cell strike and the legend swatch share the same visual
    # fragments via diagonal_strike/1. If someone changes one and forgets the
    # other, this catches it — both must contain the strike's rotation token.
    test "closed cells and the legend swatch use the same diagonal-strike fragment", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/fulfillment-calendar")

      # Sundays are closed for the delivery option set up in `setup`, so any
      # rendered Sunday in the current month carries the closed strike.
      assert html =~ "rotate-[-22deg]"
      # Legend swatch reuses the same fragment via `before:` instead of `after:`.
      assert html =~ "before:rotate-[-22deg]"
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

    test "is a no-op when the weekday is :mixed", %{
      conn: conn,
      delivery: delivery,
      pickup: pickup
    } do
      # Saturday: delivery=off, pickup=on → :mixed
      {:ok, view, _html} = live(conn, ~p"/admin/fulfillment-calendar")

      view
      |> element(~s|button[phx-click="weekday-click"][phx-value-weekday="saturday"]|)
      |> render_click()

      drain(view)

      reloaded_delivery = FulfillmentOption.get_by_id!(delivery.id, authorize?: false)
      reloaded_pickup = FulfillmentOption.get_by_id!(pickup.id, authorize?: false)

      refute :saturday in reloaded_delivery.available_days
      assert :saturday in reloaded_pickup.available_days
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

  describe "redirects" do
    test "redirects unauthenticated users to /sign-in" do
      conn = Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{})

      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/admin/fulfillment-calendar")
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

      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/admin/fulfillment-calendar")
    end
  end

  # The component sends results to the parent via send(self(), ...), which
  # land as handle_info messages. render_click only awaits the handle_event,
  # so we force a sync round-trip before asserting on persisted state.
  defp drain(view), do: _ = render(view)

  # Pick the next future date that lands on a given weekday.
  defp next_weekday(weekday_atom) do
    target = weekday_index(weekday_atom)
    today = "Europe/Helsinki" |> DateTime.now!() |> DateTime.to_date()
    offset = Enum.find(1..21, &(Date.day_of_week(Date.add(today, &1)) == target))
    Date.add(today, offset)
  end

  defp weekday_index(:monday), do: 1
  defp weekday_index(:tuesday), do: 2
  defp weekday_index(:wednesday), do: 3
  defp weekday_index(:thursday), do: 4
  defp weekday_index(:friday), do: 5
  defp weekday_index(:saturday), do: 6
  defp weekday_index(:sunday), do: 7

  # seed_generator skips the GenerateTokenChange that normal sign-in would
  # run, so we mint a token by hand and stash it in __metadata__ where
  # store_in_session/2 expects to find it.
  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end
