defmodule Edenflowers.Minimossen.WinposReportTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Minimossen.WinposReport

  defp fixture(name), do: File.read!(Path.expand("../../support/fixtures/winpos/#{name}", __DIR__))

  test "reads the week and the flowers group" do
    assert {:ok, %{week_start: ~D[2026-11-02], groups: [flowers]}} =
             WinposReport.parse(fixture("flowers-2026-11-02.XLS"))

    assert %{code: "3", name: "Eden Flowers kukat"} = flowers
    assert Decimal.equal?(flowers.gross, "154.40")
  end

  test "reads each shop group, to the cent" do
    assert {:ok, %{week_start: ~D[2026-11-02], groups: groups}} = WinposReport.parse(fixture("shop-2026-11-02.XLS"))

    assert Enum.map(groups, &{&1.code, Decimal.to_string(&1.gross, :normal)}) ==
             [{"6", "221.40"}, {"7", "160.50"}, {"66", "25.00"}]
  end

  defp rows(groups, opts \\ []) do
    [
      ["Kustannuspaikka: 1. Minimossen", nil, nil, nil, nil, "Tuoteryhmät: 66"],
      ["Jakso: Viikko", nil, nil, nil, nil, "Tuoteryhmät: 6 - 7"],
      [Keyword.get(opts, :period, "Pvm: 2.11.2026 - 8.11.2026")],
      ["Koodi", "Nimitys", nil, "Määrä", "Myynti"]
    ] ++
      Enum.map(groups, fn {code, gross} -> [code, "Group #{code}", nil, 1.0, gross] end) ++
      [["Yhteensä", nil, nil, 1.0, Keyword.get(opts, :total, groups |> Enum.map(&elem(&1, 1)) |> Enum.sum())]]
  end

  test "a covered group without sales reads 0" do
    assert {:ok, %{groups: groups}} = WinposReport.from_rows(rows([{"6", 221.4}]))

    assert Enum.map(groups, &{&1.code, Decimal.to_string(&1.gross, :normal)}) ==
             [{"6", "221.40"}, {"66", "0.00"}, {"7", "0.00"}]
  end

  test "a week without any sales still reports every covered group" do
    assert {:ok, %{week_start: ~D[2026-11-02], groups: groups}} = WinposReport.from_rows(rows([], total: 0.0))
    assert Enum.map(groups, & &1.code) == ["66", "6", "7"]
  end

  test "groups that don't add up to the total are an error" do
    assert {:error, {:winpos_report_total_mismatch, _sum, _total}} =
             WinposReport.from_rows(rows([{"6", 221.4}], total: 221.5))
  end

  test "a period that isn't a Monday-to-Sunday week is an error" do
    assert {:error, {:winpos_report_not_a_week, _from, _to}} =
             WinposReport.from_rows(rows([{"6", 221.4}], period: "Pvm: 1.11.2026 - 30.11.2026"))
  end

  test "a report that doesn't say which groups it covers is an error" do
    assert {:error, :winpos_report_groups_missing} = WinposReport.from_rows(tl(tl(rows([{"6", 221.4}]))))
  end

  test "a file that isn't a spreadsheet is an error" do
    assert {:error, {:winpos_report_unreadable, _reason}} = WinposReport.parse("%PDF-1.7 not a report")
  end
end
