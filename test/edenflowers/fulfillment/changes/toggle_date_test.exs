defmodule Edenflowers.Fulfillment.Changes.ToggleDateTest do
  use ExUnit.Case, async: true
  alias Edenflowers.Fulfillment.Changes.ToggleDate
  alias Edenflowers.Fulfillment.ShopCalendar

  describe "toggle_date/2" do
    test "closes a date when its weekday is currently available" do
      # All weekdays available, no overrides
      calendar = %ShopCalendar{}

      # 2024-04-10 is a Wednesday
      assert %{enabled_dates: [], disabled_dates: [~D[2024-04-10]]} =
               ToggleDate.toggle_date(calendar, ~D[2024-04-10])
    end

    test "opens a date when its weekday is currently disabled" do
      # Sunday off, no overrides
      calendar =
        struct!(ShopCalendar, available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday])

      # 2024-04-07 is a Sunday
      assert %{enabled_dates: [~D[2024-04-07]], disabled_dates: []} =
               ToggleDate.toggle_date(calendar, ~D[2024-04-07])
    end

    test "removes an existing off-override" do
      calendar = struct!(ShopCalendar, disabled_dates: [~D[2024-04-10]])

      assert %{enabled_dates: [], disabled_dates: []} =
               ToggleDate.toggle_date(calendar, ~D[2024-04-10])
    end

    test "removes an existing on-override" do
      calendar = struct!(ShopCalendar, enabled_dates: [~D[2024-04-07]])

      assert %{enabled_dates: [], disabled_dates: []} =
               ToggleDate.toggle_date(calendar, ~D[2024-04-07])
    end

    test "adding an off-override keeps the others" do
      calendar = struct!(ShopCalendar, disabled_dates: [~D[2024-04-15]])

      assert %{disabled_dates: dates} = ToggleDate.toggle_date(calendar, ~D[2024-04-10])
      assert ~D[2024-04-15] in dates
      assert ~D[2024-04-10] in dates
    end
  end
end
