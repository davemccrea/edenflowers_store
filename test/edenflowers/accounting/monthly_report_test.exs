defmodule Edenflowers.Accounting.MonthlyReportTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import ExUnit.CaptureLog
  import Mox

  alias Edenflowers.Accounting.MonthlyReport
  alias Edenflowers.Expenses
  alias Edenflowers.External.PapraAPI
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders.VatRow

  setup :verify_on_exit!

  setup do
    stub(StripeAPI.Mock, :list_balance_transactions_page, fn _, _ -> {:ok, %{data: [], has_more: false}} end)
    :ok
  end

  # A 25.5% product for 80.00 and a 13.5% delivery fee of 5.00.
  @two_rates [
    %VatRow{
      rate: Decimal.new("0.255"),
      base: Decimal.new("63.75"),
      vat: Decimal.new("16.25"),
      gross: Decimal.new("80.00")
    },
    %VatRow{rate: Decimal.new("0.135"), base: Decimal.new("4.41"), vat: Decimal.new("0.59"), gross: Decimal.new("5.00")}
  ]

  describe "split_by_rate/2" do
    test "a payment for the whole order matches its breakdown" do
      assert split("85.00", @two_rates) == [{"0.255", "80.00"}, {"0.135", "5.00"}]
    end

    test "a partial payment and a refund are split in the order's proportions" do
      assert split("10.00", @two_rates) == [{"0.255", "9.41"}, {"0.135", "0.59"}]
      assert split("-85.00", @two_rates) == [{"0.255", "-80.00"}, {"0.135", "-5.00"}]
      assert split("-33.33", @two_rates) == [{"0.255", "-31.37"}, {"0.135", "-1.96"}]
    end

    test "the leftover cent of a three-rate order goes on the largest rate" do
      thirds =
        for {rate, gross} <- [{"0.10", "10.00"}, {"0.255", "10.01"}, {"0.135", "10.00"}],
            do: %VatRow{rate: Decimal.new(rate), base: Decimal.new(0), vat: Decimal.new(0), gross: Decimal.new(gross)}

      # Each share rounds to 3.33, so the 0.01 left over goes on the 10.01 rate.
      assert split("10.00", thirds) == [{"0.10", "3.33"}, {"0.255", "3.34"}, {"0.135", "3.33"}]
      assert split("-10.00", thirds) == [{"0.10", "-3.33"}, {"0.255", "-3.34"}, {"0.135", "-3.33"}]
    end
  end

  test "the sales sheet splits every payment in the month by VAT rate" do
    paid = sales_order("1001")
    generate(payment(order_id: paid.id, amount: Decimal.new("85.00"), paid_at: ~U[2026-09-02 08:00:00Z]))

    partly = sales_order("1002")

    generate(
      payment(order_id: partly.id, amount: Decimal.new("10.00"), method: :zettle, paid_at: ~U[2026-09-03 08:00:00Z])
    )

    generate(
      payment(order_id: partly.id, amount: Decimal.new("75.00"), method: :mobilepay, paid_at: ~U[2026-09-04 08:00:00Z])
    )

    cancelled = sales_order("1003", fulfillment_status: :cancelled)

    generate(
      payment(order_id: cancelled.id, amount: Decimal.new("85.00"), method: :zervant, paid_at: ~U[2026-09-05 08:00:00Z])
    )

    generate(
      payment(order_id: cancelled.id, amount: Decimal.new("-33.33"), method: :cash, paid_at: ~U[2026-09-06 08:00:00Z])
    )

    booking = generate(course_registration(reference: "2001"))

    generate(
      payment(course_registration_id: booking.id, amount: Decimal.new("85.00"), paid_at: ~U[2026-09-07 08:00:00Z])
    )

    generate(
      payment(course_registration_id: booking.id, amount: Decimal.new("-85.00"), paid_at: ~U[2026-09-08 08:00:00Z])
    )

    # 00:00:30 on 1 October in Helsinki.
    generate(payment(order_id: paid.id, amount: Decimal.new("1.00"), method: :cash, paid_at: ~U[2026-09-30 21:00:30Z]))

    assert {:ok, _, zip} = MonthlyReport.build(2026, 9)
    [headings | rows] = zip |> unzip() |> Map.fetch!("rapport-2026-09.xlsx") |> read_sheet(1)

    assert headings == [
             "Betalningsdag",
             "Referens",
             "Källa",
             "Betalningssätt",
             "Momssats",
             "Exkl. moms",
             "Moms",
             "Inkl. moms"
           ]

    {sales, [[] | totals]} = Enum.split_while(rows, &(&1 != []))

    assert Enum.map(sales, &Enum.drop(&1, 1)) == [
             ["1001", "beställning", "Stripe", "0.255", "63.75", "16.25", "80.0"],
             ["1001", "beställning", "Stripe", "0.135", "4.41", "0.59", "5.0"],
             ["1002", "beställning", "Kort (Zettle)", "0.255", "7.5", "1.91", "9.41"],
             ["1002", "beställning", "Kort (Zettle)", "0.135", "0.52", "0.07", "0.59"],
             ["1002", "beställning", "MobilePay", "0.255", "56.25", "14.34", "70.59"],
             ["1002", "beställning", "MobilePay", "0.135", "3.89", "0.52", "4.41"],
             ["1003", "beställning", "Faktura (Zervant)", "0.255", "63.75", "16.25", "80.0"],
             ["1003", "beställning", "Faktura (Zervant)", "0.135", "4.41", "0.59", "5.0"],
             ["1003", "beställning", "Kontant", "0.255", "-25.0", "-6.37", "-31.37"],
             ["1003", "beställning", "Kontant", "0.135", "-1.73", "-0.23", "-1.96"],
             ["2001", "kurs", "Stripe", "0.255", "67.73", "17.27", "85.0"],
             ["2001", "kurs", "Stripe", "0.255", "-67.73", "-17.27", "-85.0"]
           ]

    assert hd(hd(sales)) == excel_date(~D[2026-09-02])
    assert hd(List.last(sales)) == excel_date(~D[2026-09-08])

    assert totals == [
             [nil, nil, nil, "Summa per momssats", "0.255", "166.25", "42.38", "208.63"],
             [nil, nil, nil, "Summa per momssats", "0.135", "11.5", "1.54", "13.04"],
             # 221.67 is every payment in the month, 85 + 10 + 75 + 85 - 33.33 + 85 - 85.
             [nil, nil, nil, "Summa", nil, "177.75", "43.92", "221.67"]
           ]

    assert {:ok, _, october} = MonthlyReport.build(2026, 10)

    assert [_headings, [_date, "1001", "beställning", "Kontant" | _] | _] =
             october |> unzip() |> Map.fetch!("rapport-2026-10.xlsx") |> read_sheet(1)
  end

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

    [headings | rows] = read_sheet(files["rapport-2026-09.xlsx"], 2)

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

  test "marks a receipt Papra can't serve as missing and still builds the report" do
    create_expense("doc-found", "Found Oy", ~D[2026-09-04], "EUR", "5.00", "1.00")
    create_expense("doc-missing", "Missing Oy", ~D[2026-09-05], "EUR", "5.00", "1.00")

    stub(PapraAPI.Mock, :fetch_document, fn
      _, "doc-found" -> {:ok, %{body: "%PDF", content_type: "application/pdf"}}
      _, "doc-missing" -> {:error, {:papra_http_error, 500}}
    end)

    {{:ok, _, zip}, log} = with_log(fn -> MonthlyReport.build(2026, 9) end)
    files = unzip(zip)

    assert log =~ "Receipt doc-missing couldn't be fetched"
    assert Map.keys(files) |> Enum.sort() == ["kvitton/001_2026-09-04_Found-Oy.pdf", "rapport-2026-09.xlsx"]

    assert [_headings, found, missing_row | _] = read_sheet(files["rapport-2026-09.xlsx"], 2)
    assert List.last(found) == "001_2026-09-04_Found-Oy.pdf"
    assert List.last(missing_row) =~ "Papra"
  end

  test "the Stripe sheet lists the month's balance transactions across every page" do
    # Helsinki midnight on 1 September and 1 October 2026.
    from = DateTime.to_unix(~U[2026-08-31 21:00:00Z])
    until = DateTime.to_unix(~U[2026-09-30 21:00:00Z])

    first_page = [
      transaction("txn_3", "payout", ~U[2026-09-20 06:00:00Z], -16_000, 0, "po_1", "STRIPE PAYOUT"),
      transaction("txn_2", "refund", ~U[2026-09-10 06:00:00Z], -2_000, 0, "re_1", "Refund for 1001")
    ]

    second_page = [
      transaction("txn_1", "charge", ~U[2026-09-02 06:00:00Z], 8_355, 145, "ch_1", "Order 1001"),
      transaction("txn_4", "stripe_fee", ~U[2026-08-31 21:30:00Z], -200, 0, "fee_1", "Radar"),
      transaction("txn_5", "adjustment", ~U[2026-09-15 06:00:00Z], 300, 0, "adj_1", nil)
    ]

    expect(StripeAPI.Mock, :list_balance_transactions_page, fn %{gte: ^from, lt: ^until}, nil ->
      {:ok, %{data: first_page, has_more: true}}
    end)

    expect(StripeAPI.Mock, :list_balance_transactions_page, fn %{gte: ^from, lt: ^until}, "txn_2" ->
      {:ok, %{data: second_page, has_more: false}}
    end)

    assert {:ok, _, zip} = MonthlyReport.build(2026, 9)
    [headings | rows] = zip |> unzip() |> Map.fetch!("rapport-2026-09.xlsx") |> read_sheet(3)

    assert headings == ["Created", "Type", "Description", "Amount", "Fee", "Net", "Payout"]

    {transactions, [[] | totals]} = Enum.split_while(rows, &(&1 != []))

    assert Enum.map(transactions, &Enum.drop(&1, 1)) == [
             ["stripe_fee", "Radar", "-2.0", "0.0", "-2.0"],
             ["charge", "Order 1001", "85.0", "1.45", "83.55"],
             ["refund", "Refund for 1001", "-20.0", "0.0", "-20.0"],
             ["adjustment", nil, "3.0", "0.0", "3.0"],
             ["payout", "STRIPE PAYOUT", "-160.0", "0.0", "-160.0", "po_1"]
           ]

    assert hd(hd(transactions)) == excel_date(~D[2026-09-01])

    # Fees are the charge's 1.45 and the 2.00 Radar fee; paid out is the one payout.
    assert totals == [
             [nil, nil, "Total fees", nil, "3.45"],
             [nil, nil, "Total payouts", nil, nil, "160.0"]
           ]
  end

  test "fails when Stripe can't be reached" do
    expect(StripeAPI.Mock, :list_balance_transactions_page, fn _, _ -> {:error, :timeout} end)

    assert {:error, :timeout} = MonthlyReport.build(2026, 9)
  end

  defp transaction(id, type, created, net, fee, source, description) do
    %{
      id: id,
      type: type,
      created: DateTime.to_unix(created),
      amount: net + fee,
      fee: fee,
      net: net,
      source: source,
      description: description
    }
  end

  defp split(amount, breakdown) do
    for {rate, gross} <- MonthlyReport.split_by_rate(Decimal.new(amount), breakdown),
        do: {Decimal.to_string(rate), Decimal.to_string(gross)}
  end

  defp sales_order(reference, attrs \\ []) do
    generate(order([state: :placed, order_reference: reference, vat_breakdown: @two_rates] ++ attrs))
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

  # Reads a sheet back as rows of cell text, with nil for skipped cells.
  defp read_sheet(xlsx, number) do
    files = unzip(xlsx)

    strings =
      ~r{<si>.*?<t[^>]*>(.*?)</t>.*?</si>}s
      |> Regex.scan(files["xl/sharedStrings.xml"], capture: :all_but_first)
      |> Enum.map(fn [text] -> unescape(text) end)

    ~r{<row[^>]*>(.*?)</row>}s
    |> Regex.scan(files["xl/worksheets/sheet#{number}.xml"], capture: :all_but_first)
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
