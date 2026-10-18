defmodule Edenflowers.Accounting.MonthlyReportTest do
  use Edenflowers.DataCase, async: true

  import Mox

  alias Edenflowers.Accounting.MonthlyReport
  alias Edenflowers.Expenses
  alias Edenflowers.External.PapraAPI

  setup :verify_on_exit!

  test "zips the month's expense sheet with every receipt it names" do
    create_expense("doc-adobe", "Adobe", ~D[2026-09-11], "SEK", "120.00", "24.00")

    "doc-kukka"
    |> create_expense("Kukkatukku Oy", ~D[2026-09-03], "EUR", "125.50", "25.50")
    |> Expenses.mark_expense_reviewed!(authorize?: false)

    create_expense("doc-tools", "Työkalu Åb", ~D[2026-09-20], "EUR", "10.00", "2.00")
    create_expense("doc-august", "August Oy", ~D[2026-08-31], "EUR", "1.00", "0.20")

    stub(PapraAPI.Mock, :fetch_document, fn "org_test", document_id ->
      {:ok, %{body: "%PDF #{document_id}", content_type: "application/pdf"}}
    end)

    assert {:ok, "redovisning-2026-09.zip", zip} = MonthlyReport.build(2026, 9)
    files = unzip(zip)

    assert Map.keys(files) |> Enum.sort() == [
             "kvitton/001_2026-09-03_Kukkatukku-Oy.pdf",
             "kvitton/002_2026-09-11_Adobe.pdf",
             "kvitton/003_2026-09-20_Tyokalu-Ab.pdf",
             "rapport-2026-09.xlsx"
           ]

    assert files["kvitton/002_2026-09-11_Adobe.pdf"] == "%PDF doc-adobe"

    [headings | rows] = read_sheet(files["rapport-2026-09.xlsx"])

    assert headings == [
             "Nr",
             "Betalningsdag",
             "Fakturadatum",
             "Leverantör",
             "Leverantörens momsnummer",
             "Kategori",
             "Beskrivning",
             "Valuta",
             "Totalt",
             "Moms",
             "Exkl. moms",
             "Granskad",
             "Kvittofil"
           ]

    assert [
             [
               "1",
               paid,
               invoiced,
               "Kukkatukku Oy",
               "FI12345678",
               "Kontorsmaterial",
               "Supplies",
               "EUR",
               "125.5",
               "25.5",
               "100.0",
               "ja",
               "001_2026-09-03_Kukkatukku-Oy.pdf"
             ],
             ["2" | _] = adobe,
             ["3" | _],
             [],
             [nil, nil, nil, nil, nil, nil, "Summa", "EUR", "135.5", "27.5", "108.0"],
             [nil, nil, nil, nil, nil, nil, "Summa", "SEK", "120.0", "24.0", "96.0"]
           ] = rows

    assert paid == excel_date(~D[2026-09-03])
    assert invoiced == paid
    assert List.last(adobe) == "002_2026-09-11_Adobe.pdf"
    assert Enum.at(adobe, 11) == "nej"
  end

  test "counts an invoice in the month it was paid" do
    "doc-late"
    |> create_expense("Late Oy", ~D[2026-08-25], "EUR", "50.00", "10.00")
    |> Expenses.correct_expense!(%{paid_on: ~D[2026-09-02]}, authorize?: false)

    stub(PapraAPI.Mock, :fetch_document, fn _, _ -> {:ok, %{body: "%PDF", content_type: "application/pdf"}} end)

    assert {:ok, _, august} = MonthlyReport.build(2026, 8)
    refute Map.has_key?(unzip(august), "kvitton/001_2026-09-02_Late-Oy.pdf")
    assert Map.keys(unzip(august)) == ["rapport-2026-08.xlsx"]

    assert {:ok, _, september} = MonthlyReport.build(2026, 9)
    assert Map.has_key?(unzip(september), "kvitton/001_2026-09-02_Late-Oy.pdf")
  end

  test "leaves out expenses with no date" do
    create_expense("doc-undated", "Undated Oy", nil, "EUR", "5.00", "1.00")

    assert {:ok, _, zip} = MonthlyReport.build(2026, 9)
    assert Map.keys(unzip(zip)) == ["rapport-2026-09.xlsx"]
  end

  test "fails when a receipt can't be fetched" do
    create_expense("doc-missing", "Missing Oy", ~D[2026-09-05], "EUR", "5.00", "1.00")

    expect(PapraAPI.Mock, :fetch_document, fn _, _ -> {:error, {:papra_http_error, 500}} end)

    assert {:error, _} = MonthlyReport.build(2026, 9)
  end

  defp create_expense(document_id, vendor, date, currency, total, vat) do
    Expenses.ingest_expense!(
      %{
        document_id: document_id,
        vendor_name: vendor,
        vendor_vat_number: "FI12345678",
        date: date,
        total_amount: total,
        vat_amount: vat,
        currency: String.downcase(currency),
        category: "office_supplies",
        description: "Supplies",
        confidence: "high"
      },
      authorize?: false
    )
  end

  defp excel_date(date), do: "#{Date.diff(date, ~D[1899-12-30])}.0"

  defp unzip(zip) do
    {:ok, files} = :zip.unzip(zip, [:memory])
    Map.new(files, fn {name, body} -> {to_string(name), body} end)
  end

  # Reads the first sheet back as rows of cell text, with nil for skipped cells.
  defp read_sheet(xlsx) do
    files = unzip(xlsx)

    strings =
      ~r{<si>.*?<t[^>]*>(.*?)</t>.*?</si>}s
      |> Regex.scan(files["xl/sharedStrings.xml"], capture: :all_but_first)
      |> Enum.map(fn [text] -> unescape(text) end)

    ~r{<row[^>]*>(.*?)</row>}s
    |> Regex.scan(files["xl/worksheets/sheet1.xml"], capture: :all_but_first)
    |> Enum.map(fn [cells] -> read_row(cells, strings) end)
  end

  defp read_row(cells, strings) do
    ~r{<c r="([A-Z]+)\d+"([^>]*)>\s*<v>(.*?)</v>\s*</c>}s
    |> Regex.scan(cells, capture: :all_but_first)
    |> Enum.reduce({[], 0}, fn [column, attrs, value], {row, next} ->
      index = :binary.first(column) - ?A
      padding = List.duplicate(nil, index - next)
      text = if attrs =~ ~s(t="s"), do: Enum.at(strings, String.to_integer(value)), else: value
      {row ++ padding ++ [text], index + 1}
    end)
    |> elem(0)
  end

  defp unescape(text),
    do: text |> String.replace("&amp;", "&") |> String.replace("&lt;", "<") |> String.replace("&gt;", ">")
end
