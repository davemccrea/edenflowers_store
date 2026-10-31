defmodule EdenflowersWeb.StoreCalendarTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Edenflowers.Fulfillment.Availability
  alias Edenflowers.ShopTime
  alias EdenflowersWeb.StoreCalendar

  describe "update/2 — view_date sync with selected_date" do
    test "advances view_date to the month of selected_date when it falls outside today's month" do
      # selected_date is two months from today; with no sync, the calendar
      # would render today's month and the selected pill would be invisible
      # (cells outside the view month render with opacity-0).
      future_date = ShopTime.today() |> Date.shift(month: 2) |> Date.to_iso8601()

      html =
        render_component(&StoreCalendar.store_calendar/1,
          id: "calendar",
          calendar: Edenflowers.Fulfillment.get_shop_calendar!(),
          selected_date: future_date
        )

      expected_header =
        future_date
        |> Date.from_iso8601!()
        |> Localize.DateTime.to_string!(format: "MMMM y")

      assert html =~ expected_header
      assert html =~ ~s(aria-pressed="true")
    end

    test "leaves view_date alone when selected_date is already in the current view month" do
      today_iso = ShopTime.today() |> Date.to_iso8601()

      html =
        render_component(&StoreCalendar.store_calendar/1,
          id: "calendar",
          calendar: Edenflowers.Fulfillment.get_shop_calendar!(),
          selected_date: today_iso
        )

      expected_header =
        ShopTime.today()
        |> Localize.DateTime.to_string!(format: "MMMM y")

      assert html =~ expected_header
    end

    test "with no selected_date, opens on the month of the next open date" do
      calendar = Edenflowers.Fulfillment.get_shop_calendar!()

      html =
        render_component(&StoreCalendar.store_calendar/1,
          id: "calendar",
          calendar: calendar,
          selected_date: nil
        )

      expected_header =
        Availability.next_open_date(calendar, ShopTime.now())
        |> Localize.DateTime.to_string!(format: "MMMM y")

      assert html =~ expected_header
      refute html =~ ~s(aria-pressed="true")
    end
  end

  # The id, key targets and tabindex all come from the slot's `attrs`, so this
  # fails if StoreCalendar stops spreading them on its day buttons.
  test "each day carries what CalendarHook needs, out of the Tab order" do
    calendar = Edenflowers.Fulfillment.get_shop_calendar!()

    html =
      render_component(&StoreCalendar.store_calendar/1,
        id: "calendar",
        calendar: calendar,
        selected_date: nil
      )

    open_date = Availability.next_open_date(calendar, ShopTime.now())
    selector = ~s|button#calendar-day-#{open_date}[data-key-targets][tabindex="-1"]|
    assert html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count() == 1
  end
end
