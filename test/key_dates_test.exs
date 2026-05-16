defmodule Edenflowers.Store.KeyDatesTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Store.KeyDates

  describe "for_year/1" do
    test "materialises the five known key dates for 2026" do
      by_name = KeyDates.for_year(2026) |> Map.new(fn %{name: n, date: d} -> {n, d} end)

      assert by_name["Valentine's Day"] == ~D[2026-02-14]
      assert by_name["Women's Day"] == ~D[2026-03-08]
      assert by_name["Mother's Day"] == ~D[2026-05-10]
      assert by_name["Father's Day"] == ~D[2026-11-08]
      assert by_name["Christmas Eve"] == ~D[2026-12-24]
    end

    test "nth-weekday rule shifts year-over-year" do
      mothers_day = fn year ->
        KeyDates.for_year(year)
        |> Enum.find(&(&1.name == "Mother's Day"))
        |> Map.fetch!(:date)
      end

      assert mothers_day.(2026) == ~D[2026-05-10]
      assert mothers_day.(2027) == ~D[2027-05-09]
      assert mothers_day.(2028) == ~D[2028-05-14]
    end

    test "every entry has a heroicon name and a human-readable name" do
      for %{name: name, icon: icon} <- KeyDates.for_year(2026) do
        assert is_binary(name) and name != ""
        assert String.starts_with?(icon, "hero-")
      end
    end
  end

  describe "icon_for/1" do
    test "returns the icon for each key date in 2026" do
      assert KeyDates.icon_for(~D[2026-02-14]) == "hero-heart-solid"
      assert KeyDates.icon_for(~D[2026-03-08]) == "hero-sparkles-solid"
      assert KeyDates.icon_for(~D[2026-05-10]) == "hero-heart-solid"
      assert KeyDates.icon_for(~D[2026-11-08]) == "hero-heart-solid"
      assert KeyDates.icon_for(~D[2026-12-24]) == "hero-gift-solid"
    end

    test "tracks the right year — Mother's Day shifts across years" do
      assert KeyDates.icon_for(~D[2027-05-09]) == "hero-heart-solid"
      assert KeyDates.icon_for(~D[2028-05-14]) == "hero-heart-solid"
      assert KeyDates.icon_for(~D[2027-05-10]) == nil
    end

    test "returns nil for non-key dates" do
      assert KeyDates.icon_for(~D[2026-06-15]) == nil
    end
  end
end
