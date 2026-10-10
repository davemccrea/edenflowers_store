defmodule Edenflowers.Fulfillment.KeyDatesTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Fulfillment.KeyDates

  describe "for_year/1" do
    test "materialises the four known key dates for 2026" do
      by_key = KeyDates.for_year(2026) |> Map.new(fn %{key: k, date: d} -> {k, d} end)

      assert by_key == %{
               valentines_day: ~D[2026-02-14],
               womens_day: ~D[2026-03-08],
               mothers_day: ~D[2026-05-10],
               fathers_day: ~D[2026-11-08]
             }
    end

    test "nth-weekday rule shifts year-over-year" do
      mothers_day = fn year ->
        KeyDates.for_year(year)
        |> Enum.find(&(&1.key == :mothers_day))
        |> Map.fetch!(:date)
      end

      assert mothers_day.(2026) == ~D[2026-05-10]
      assert mothers_day.(2027) == ~D[2027-05-09]
      assert mothers_day.(2028) == ~D[2028-05-14]
    end
  end

  describe "for_month/1" do
    test "returns only the key dates in that month" do
      assert KeyDates.for_month(~D[2026-11-20]) == [%{key: :fathers_day, date: ~D[2026-11-08]}]
    end

    test "is empty for a month without key dates" do
      assert KeyDates.for_month(~D[2026-06-01]) == []
    end
  end

  describe "lookup_for/1" do
    test "returns the key for each key date in 2026" do
      assert KeyDates.lookup_for(~D[2026-02-14]) == :valentines_day
      assert KeyDates.lookup_for(~D[2026-03-08]) == :womens_day
      assert KeyDates.lookup_for(~D[2026-05-10]) == :mothers_day
      assert KeyDates.lookup_for(~D[2026-11-08]) == :fathers_day
    end

    test "tracks the right year — Mother's Day shifts across years" do
      assert KeyDates.lookup_for(~D[2027-05-09]) == :mothers_day
      assert KeyDates.lookup_for(~D[2028-05-14]) == :mothers_day
      assert KeyDates.lookup_for(~D[2027-05-10]) == nil
    end

    test "returns nil for non-key dates" do
      assert KeyDates.lookup_for(~D[2026-06-15]) == nil
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
