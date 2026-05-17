defmodule Edenflowers.Store.KeyDatesTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Store.KeyDates

  describe "for_year/1" do
    test "materialises the four known key dates for 2026" do
      by_name = KeyDates.for_year(2026) |> Map.new(fn %{name: n, date: d} -> {n, d} end)

      assert by_name["Valentine's Day"] == ~D[2026-02-14]
      assert by_name["Women's Day"] == ~D[2026-03-08]
      assert by_name["Mother's Day"] == ~D[2026-05-10]
      assert by_name["Father's Day"] == ~D[2026-11-08]
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

  describe "lookup_for/1" do
    test "returns the icon and colour for each key date in 2026" do
      for date <- [~D[2026-02-14], ~D[2026-03-08], ~D[2026-05-10], ~D[2026-11-08]] do
        assert %{icon: "hero-heart", colour_class: "text-" <> _} = KeyDates.lookup_for(date)
      end
    end

    test "tracks the right year — Mother's Day shifts across years" do
      assert %{icon: "hero-heart"} = KeyDates.lookup_for(~D[2027-05-09])
      assert %{icon: "hero-heart"} = KeyDates.lookup_for(~D[2028-05-14])
      assert KeyDates.lookup_for(~D[2027-05-10]) == nil
    end

    test "returns nil for non-key dates" do
      assert KeyDates.lookup_for(~D[2026-06-15]) == nil
    end

    test "returns a distinct colour class for each key date" do
      colours =
        [~D[2026-02-14], ~D[2026-03-08], ~D[2026-05-10], ~D[2026-11-08]]
        |> Enum.map(&KeyDates.lookup_for/1)
        |> Enum.map(& &1.colour_class)

      assert Enum.uniq(colours) == colours
    end
  end

  describe "key_date?/1" do
    test "true for a known key date" do
      assert KeyDates.key_date?(~D[2026-02-14])
    end

    test "false for an ordinary date" do
      refute KeyDates.key_date?(~D[2026-06-15])
    end
  end
end
