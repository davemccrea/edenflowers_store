defmodule EdenflowersWeb.DatePickerTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EdenflowersWeb.DatePicker

  describe "update/2 — view_date sync with selected_date" do
    test "advances view_date to the month of selected_date when it falls outside today's month" do
      # selected_date is two months from today; with no sync, the calendar
      # would render today's month and the selected pill would be invisible
      # (cells outside the view month render with opacity-0).
      future_date = Date.utc_today() |> Date.shift(month: 2) |> Date.to_iso8601()

      html =
        render_component(DatePicker,
          id: "calendar",
          field: nil,
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
      today_iso = Date.utc_today() |> Date.to_iso8601()

      html =
        render_component(DatePicker,
          id: "calendar",
          field: nil,
          selected_date: today_iso
        )

      expected_header =
        Date.utc_today()
        |> Localize.DateTime.to_string!(format: "MMMM y")

      assert html =~ expected_header
    end

    test "with no selected_date, renders today's month" do
      html =
        render_component(DatePicker,
          id: "calendar",
          field: nil,
          selected_date: nil
        )

      expected_header =
        Date.utc_today()
        |> Localize.DateTime.to_string!(format: "MMMM y")

      assert html =~ expected_header
      refute html =~ ~s(aria-pressed="true")
    end
  end
end
