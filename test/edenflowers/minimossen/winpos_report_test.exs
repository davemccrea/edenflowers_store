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

  test "a file that isn't a spreadsheet is an error" do
    assert {:error, {:winpos_report_unreadable, _reason}} = WinposReport.parse("%PDF-1.7 not a report")
  end
end
