defmodule Edenflowers.Minimossen.RecentSalesTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Minimossen

  defp record(week_start, code, gross) do
    Minimossen.record_minimossen_sales!(
      %{week_start: week_start, group_code: code, group_name: "Group #{code}", gross: gross},
      actor: Edenflowers.Actors.system_actor()
    )
  end

  defp summary(count, period \\ :week),
    do: Minimossen.recent_minimossen_sales!([count: count, period: period], actor: generate(admin_user()))

  defp recent(count, period \\ :week) do
    Enum.map(
      summary(count, period).periods,
      &{&1.start, Map.new(&1.groups, fn {code, gross} -> {code, amount(gross)} end)}
    )
  end

  defp average(count) do
    case List.last(summary(count).periods).average do
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

    assert recent(2) == [
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

  test "a week without sales, named only by its code, doesn't rename the group" do
    record(~D[2026-10-26], "7", "160.50")

    Minimossen.record_minimossen_sales!(
      %{week_start: ~D[2026-11-02], group_code: "7", group_name: "7", gross: "0.00"},
      actor: Edenflowers.Actors.system_actor()
    )

    assert summary(2).groups == [%{code: "7", name: "Group 7"}]
  end

  test "a week without a report reads 0" do
    record(~D[2026-10-19], "3", "100.00")
    record(~D[2026-11-02], "3", "154.40")

    assert [_, {~D[2026-10-26], %{"3" => "0"}}, _] = recent(3)
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

  test "each week compares with the 8 weeks before it" do
    record(~D[2026-10-12], "3", "40.00")
    record(~D[2026-10-19], "3", "100.00")
    record(~D[2026-10-26], "3", "999.00")

    assert [first, second, _latest] = summary(3).periods
    assert first.average == nil
    assert amount(second.average.total) == "40.00"
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

    assert %{total: total, first_week_start: ~D[2025-12-29], last_week_start: ~D[2026-11-02]} = summary(12).year
    assert amount(total) == "475.80"
  end

  test "totals each month, counting a week in the month its Thursday falls in" do
    # Thursday 2026-10-01: October.
    record(~D[2026-09-28], "3", "100.00")
    # Thursday 2026-09-24: September.
    record(~D[2026-09-21], "3", "10.00")
    record(~D[2026-10-26], "3", "50.00")
    record(~D[2026-10-26], "6", "5.00")

    assert recent(3, :month) == [
             {~D[2026-09-01], %{"3" => "10.00", "6" => "0"}},
             {~D[2026-10-01], %{"3" => "150.00", "6" => "5.00"}}
           ]

    assert Enum.all?(summary(3, :month).periods, &(&1.average == nil))
  end

  test "totals each ISO year from the first with a report" do
    record(~D[2024-12-23], "3", "7.00")
    # Week 1 of 2026 starts in December.
    record(~D[2025-12-29], "3", "100.00")
    record(~D[2026-11-02], "3", "54.40")

    assert recent(12, :year) == [
             {~D[2024-01-01], %{"3" => "7.00"}},
             {~D[2025-01-01], %{"3" => "0"}},
             {~D[2026-01-01], %{"3" => "154.40"}}
           ]
  end

  test "nothing before the first import" do
    assert summary(12) == %{groups: [], periods: [], year: nil}
  end

  test "only admins see them" do
    assert_raise Ash.Error.Forbidden, fn ->
      Minimossen.recent_minimossen_sales!(actor: nil)
    end
  end
end
