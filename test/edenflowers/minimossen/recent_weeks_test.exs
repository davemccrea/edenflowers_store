defmodule Edenflowers.Minimossen.RecentWeeksTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Minimossen

  defp record(week_start, code, gross) do
    Minimossen.record_minimossen_sales!(
      %{week_start: week_start, group_code: code, group_name: "Group #{code}", gross: gross},
      actor: Edenflowers.Actors.system_actor()
    )
  end

  defp summary(count), do: Minimossen.recent_minimossen_weeks!([count: count], actor: generate(admin_user()))

  defp recent_weeks(count) do
    Enum.map(summary(count).weeks, &{&1.week_start, Map.new(&1.groups, fn {code, gross} -> {code, amount(gross)} end)})
  end

  defp average(count) do
    case summary(count).average do
      nil -> nil
      average -> {amount(average.groups["3"]), amount(average.groups["6"]), amount(average.total)}
    end
  end

  defp amount(decimal), do: Decimal.to_string(decimal, :normal)

  test "splits each week by product group, ending at the latest week imported" do
    record(~D[2026-10-19], "3", "100.00")
    record(~D[2026-10-26], "6", "10.00")
    record(~D[2026-11-02], "3", "154.40")
    record(~D[2026-11-02], "6", "221.40")
    record(~D[2026-11-02], "66", "25.00")

    assert recent_weeks(2) == [
             {~D[2026-10-26], %{"3" => "0", "6" => "10.00", "66" => "0"}},
             {~D[2026-11-02], %{"3" => "154.40", "6" => "221.40", "66" => "25.00"}}
           ]
  end

  test "lists the groups by code as a number, named as the latest report names them" do
    record(~D[2026-10-26], "66", "1.00")
    record(~D[2026-10-26], "3", "1.00")

    Minimossen.record_minimossen_sales!(
      %{week_start: ~D[2026-11-02], group_code: "3", group_name: "Eden Flowers kukat", gross: "1.00"},
      actor: Edenflowers.Actors.system_actor()
    )

    assert summary(2).groups == [%{code: "3", name: "Eden Flowers kukat"}, %{code: "66", name: "Group 66"}]
  end

  test "a week without a report reads 0" do
    record(~D[2026-10-19], "3", "100.00")
    record(~D[2026-11-02], "3", "154.40")

    assert [_, {~D[2026-10-26], %{"3" => "0"}}, _] = recent_weeks(3)
  end

  test "averages the 8 weeks before the latest, leaving out the latest and weeks without a report" do
    # 9 weeks before the latest: outside the average.
    record(~D[2026-08-31], "3", "1000.00")
    record(~D[2026-09-07], "3", "100.00")
    record(~D[2026-09-07], "6", "300.00")
    # 2026-09-14 to 2026-10-19 have no report.
    record(~D[2026-10-26], "3", "51.00")
    record(~D[2026-10-26], "6", "250.00")
    record(~D[2026-11-02], "3", "999.00")

    # Shown weeks don't limit the average, so even 1 week compares with the 8 before it.
    assert average(1) == {"75.50", "275.00", "350.50"}
  end

  test "no average without a report before the latest" do
    record(~D[2026-11-02], "3", "154.40")

    assert average(12) == nil
  end

  test "totals the latest week's year from its first week imported, by ISO week" do
    # Week 52 of 2025.
    record(~D[2025-12-22], "3", "500.00")
    # Week 1 of 2026 starts in December.
    record(~D[2025-12-29], "3", "100.00")
    record(~D[2026-11-02], "3", "154.40")
    record(~D[2026-11-02], "6", "221.40")

    assert %{total: total, first_week_start: ~D[2025-12-29]} = summary(12).year
    assert amount(total) == "475.80"
  end

  test "nothing before the first import" do
    assert summary(12) == %{groups: [], weeks: [], average: nil, year: nil}
  end

  test "only admins see them" do
    assert_raise Ash.Error.Forbidden, fn ->
      Minimossen.recent_minimossen_weeks!(actor: nil)
    end
  end
end
