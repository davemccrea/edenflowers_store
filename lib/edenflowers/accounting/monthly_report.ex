defmodule Edenflowers.Accounting.MonthlyReport do
  @moduledoc """
  Builds the zip Jennie sends her accountant each month: a spreadsheet of the
  month's sales, expenses and Stripe fees and payouts, and every receipt PDF
  behind the expenses, in Swedish.

  VAT is reported on a cash basis, so a payment counts in the month of its
  `paid_at` (Helsinki time), and an expense in the month it was paid: its
  `paid_on`, or its `date` when that's empty. The sales sheet is the shop's only
  sales record (ADR 0004), so every payment method counts.

  A receipt Papra can't serve doesn't stop the report: its row says so.
  """
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin", context: "accounting report"]

  require Ash.Query
  require Logger

  alias Edenflowers.Expenses.Expense
  alias Edenflowers.External.PapraAPI
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders.Calculations.Vat
  alias Edenflowers.Payments.Payment
  alias Edenflowers.ShopTime
  alias EdenflowersWeb.Admin.Components
  alias EdenflowersWeb.Admin.OrderLog
  alias Elixlsx.Sheet
  alias Elixlsx.Workbook

  def build(year, month) do
    Gettext.with_locale(EdenflowersWeb.Gettext, "sv", fn -> build_zip(year, month) end)
  end

  defp build_zip(year, month) do
    first = Date.new!(year, month, 1)
    label = first |> Date.to_iso8601() |> String.slice(0, 7)
    spreadsheet = "rapport-#{label}.xlsx"

    last = Date.end_of_month(first)

    with {:ok, payments} <- payments(first, last),
         {:ok, expenses} <- paid_expenses(first, last),
         rows =
           expenses
           |> Enum.with_index(1)
           |> Task.async_stream(&fetch_receipt/1, max_concurrency: 5, timeout: :infinity)
           |> Enum.map(fn {:ok, row} -> row end),
         receipts = for({_n, _expense, name, body} <- rows, body, do: {~c"kvitton/#{name}", body}),
         {:ok, transactions} <-
           StripeAPI.list_balance_transactions(helsinki_midnight_utc(first), helsinki_midnight_utc(Date.add(last, 1))),
         sheets = [sales_sheet(payments), expenses_sheet(rows), stripe_sheet(transactions)],
         workbook = %Workbook{sheets: Enum.map(sheets, &with_basic_font/1)},
         {:ok, {_, xlsx}} <- Elixlsx.write_to_memory(workbook, spreadsheet),
         files = [{~c"#{spreadsheet}", xlsx} | receipts],
         {:ok, {_, zip}} <- :zip.create(~c"redovisning-#{label}.zip", files, [:memory]) do
      {:ok, "redovisning-#{label}.zip", zip}
    end
  end

  defp payments(first, last) do
    from = helsinki_midnight_utc(first)
    until = helsinki_midnight_utc(Date.add(last, 1))

    Payment
    |> Ash.Query.filter(paid_at >= ^from and paid_at < ^until)
    |> Ash.Query.sort(paid_at: :asc)
    |> Ash.Query.load(order: [:order_reference, :vat_breakdown], course_registration: [:reference, :tax_rate])
    |> Ash.read(authorize?: false)
  end

  defp helsinki_midnight_utc(date) do
    date
    |> DateTime.new!(~T[00:00:00], ShopTime.timezone())
    |> DateTime.shift_zone!("Etc/UTC")
  end

  @doc """
  Splits a payment across an order's VAT breakdown by each rate's share of the
  order's gross, as `{rate, gross}` pairs. Each share is rounded to the cent and
  any leftover cent goes on the rate with the largest gross, so the shares
  always sum to the payment.
  """
  def split_by_rate(amount, vat_breakdown) do
    order_gross = vat_breakdown |> Enum.map(& &1.gross) |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    shares =
      Enum.map(vat_breakdown, fn row ->
        {row.rate, amount |> Decimal.mult(row.gross) |> Decimal.div(order_gross) |> Decimal.round(2)}
      end)

    leftover = Decimal.sub(amount, shares |> Enum.map(&elem(&1, 1)) |> Enum.reduce(Decimal.new(0), &Decimal.add/2))
    largest = vat_breakdown |> Enum.max_by(& &1.gross, Decimal) |> Map.fetch!(:rate)

    Enum.map(shares, fn
      {^largest, gross} -> {largest, Decimal.add(gross, leftover)}
      share -> share
    end)
  end

  defp sales_sheet(payments) do
    rows = Enum.flat_map(payments, &sale_rows/1)

    headings = [
      ~t"Paid date",
      ~t"Reference",
      ~t"Source",
      ~t"Payment method",
      ~t"VAT rate",
      ~t"Net",
      ~t"VAT",
      ~t"Gross"
    ]

    rate_totals =
      rows
      |> Enum.group_by(& &1.rate)
      |> Enum.sort_by(fn {rate, _} -> rate end, {:desc, Decimal})
      |> Enum.map(fn {rate, rate_rows} ->
        [nil, nil, nil, [~t"Total per VAT rate", bold: true], rate_cell(rate) | sale_totals(rate_rows)]
      end)

    grand_total = [nil, nil, nil, [~t"Sum", bold: true], nil | sale_totals(rows)]

    %Sheet{
      name: "Försäljning",
      rows:
        [Enum.map(headings, &[&1, bold: true]) | Enum.map(rows, &sale_row/1)] ++ [[]] ++ rate_totals ++ [grand_total]
    }
  end

  defp sale_rows(%Payment{order: %{} = order} = payment) do
    for {rate, gross} <- split_by_rate(payment.amount, order.vat_breakdown),
        do: sale(payment, order.order_reference, ~t"order", rate, gross)
  end

  defp sale_rows(%Payment{course_registration: registration} = payment) do
    [sale(payment, registration.reference, ~t"course", registration.tax_rate, payment.amount)]
  end

  defp sale(payment, reference, source, rate, gross) do
    net = Vat.net_of_vat(gross, rate)

    %{
      date: payment.paid_at |> DateTime.shift_zone!(ShopTime.timezone()) |> DateTime.to_date(),
      reference: reference,
      source: source,
      method: OrderLog.payment_method_label(payment.method),
      # Normalised, so the same rate read from an order and a booking totals together.
      rate: Decimal.normalize(rate),
      net: net,
      vat: Decimal.sub(gross, net),
      gross: gross
    }
  end

  defp sale_row(sale) do
    [
      date_cell(sale.date),
      sale.reference,
      sale.source,
      sale.method,
      rate_cell(sale.rate),
      amount_cell(sale.net),
      amount_cell(sale.vat),
      amount_cell(sale.gross)
    ]
  end

  defp sale_totals(rows) do
    for field <- [:net, :vat, :gross] do
      rows |> Enum.map(&Map.fetch!(&1, field)) |> Enum.reduce(Decimal.new("0.00"), &Decimal.add/2) |> amount_cell()
    end
  end

  defp rate_cell(rate), do: [Decimal.to_float(rate), num_format: "0.0%"]

  defp paid_expenses(first, last) do
    with {:ok, expenses} <-
           Expense
           |> Ash.Query.filter((paid_on || date) >= ^first and (paid_on || date) <= ^last)
           |> Ash.read(authorize?: false) do
      {:ok, Enum.sort_by(expenses, &{Date.to_iso8601(paid_date(&1)), &1.vendor_name || ""})}
    end
  end

  defp paid_date(expense), do: expense.paid_on || expense.date

  defp receipt_name(n, expense) do
    number = n |> Integer.to_string() |> String.pad_leading(3, "0")
    "#{number}_#{Date.to_iso8601(paid_date(expense))}_#{ascii_vendor(expense.vendor_name)}.pdf"
  end

  defp ascii_vendor(nil), do: ""

  defp ascii_vendor(vendor) do
    vendor
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/[^A-Za-z0-9-]/, "")
  end

  defp fetch_receipt({expense, n}) do
    organization_id = Application.get_env(:edenflowers, :papra_organization_id)

    case PapraAPI.impl().fetch_document(organization_id, expense.document_id) do
      {:ok, %{body: body}} ->
        {n, expense, receipt_name(n, expense), body}

      {:error, error} ->
        Logger.warning("Receipt #{expense.document_id} couldn't be fetched for the monthly report: #{inspect(error)}")
        {n, expense, nil, nil}
    end
  end

  defp expenses_sheet(rows) do
    headings = [
      ~t"Row number",
      ~t"Paid date",
      ~t"Invoice date",
      ~t"Vendor",
      ~t"Vendor VAT number",
      ~t"Category",
      ~t"Description",
      ~t"Currency",
      ~t"Total",
      ~t"VAT",
      ~t"Net",
      ~t"Reviewed",
      ~t"Receipt file"
    ]

    %Sheet{
      name: "Inköp",
      rows: [Enum.map(headings, &[&1, bold: true]) | Enum.map(rows, &expense_row/1)] ++ [[]] ++ currency_totals(rows)
    }
  end

  defp expense_row({n, expense, receipt, _body}) do
    [
      n,
      date_cell(paid_date(expense)),
      date_cell(expense.date),
      expense.vendor_name,
      expense.vendor_vat_number,
      expense.category && Components.category_label(expense.category),
      expense.description,
      currency(expense.currency),
      amount_cell(expense.total_amount),
      amount_cell(expense.vat_amount),
      amount_cell(net(expense)),
      if(expense.reviewed_at, do: ~t"yes", else: ~t"no"),
      receipt || ~t"Missing: couldn't be fetched from Papra"
    ]
  end

  defp currency_totals(rows) do
    rows
    |> Enum.map(fn {_n, expense, _receipt, _body} -> expense end)
    |> Enum.group_by(&currency(&1.currency))
    |> Enum.sort_by(fn {currency, _} -> currency end)
    |> Enum.map(fn {currency, expenses} ->
      [nil, nil, nil, nil, nil, nil, [~t"Sum", bold: true], currency] ++
        Enum.map([& &1.total_amount, & &1.vat_amount, &net/1], fn amount ->
          expenses
          |> Enum.map(amount)
          |> Enum.reject(&is_nil/1)
          |> Enum.reduce(Decimal.new("0.00"), &Decimal.add/2)
          |> amount_cell()
        end)
    end)
  end

  defp net(%{total_amount: nil}), do: nil
  defp net(%{total_amount: total, vat_amount: nil}), do: total
  defp net(%{total_amount: total, vat_amount: vat}), do: Decimal.sub(total, vat)

  defp currency(nil), do: nil
  defp currency(currency), do: currency |> to_string() |> String.upcase()

  # Stripe's rows are not sales: they let the accountant book Stripe's fees and
  # match its payouts, which arrive in the bank net of fees. The sheet keeps
  # Stripe's own English terms so it reads like the Stripe dashboard.
  defp stripe_sheet(transactions) do
    headings = ["Created", "Type", "Description", "Amount", "Fee", "Net", "Payout"]

    rows =
      transactions
      |> Enum.sort_by(& &1.created)
      |> Enum.map(fn transaction ->
        [
          transaction.created
          |> DateTime.from_unix!()
          |> DateTime.shift_zone!(ShopTime.timezone())
          |> DateTime.to_date()
          |> date_cell(),
          transaction.type,
          transaction.description,
          stripe_amount_cell(transaction.amount),
          stripe_amount_cell(transaction.fee),
          stripe_amount_cell(transaction.net),
          if(transaction.type == "payout", do: transaction.source)
        ]
      end)

    # A charge's fee is in its fee column; a fee Stripe charges on its own
    # (Radar, currency conversion) is a row whose net is the negative fee.
    fees =
      Enum.sum_by(transactions, & &1.fee) -
        (transactions |> Enum.filter(&fee_type?(&1.type)) |> Enum.sum_by(& &1.net))

    paid_out = transactions |> Enum.filter(&(&1.type == "payout")) |> Enum.sum_by(&(-&1.net))

    %Sheet{
      name: "Stripe",
      rows:
        [Enum.map(headings, &[&1, bold: true]) | rows] ++
          [
            [],
            [nil, nil, ["Total fees", bold: true], nil, stripe_amount_cell(fees)],
            [nil, nil, ["Total payouts", bold: true], nil, nil, stripe_amount_cell(paid_out)]
          ]
    }
  end

  defp fee_type?(type), do: type in ["stripe_fee", "stripe_fx_fee", "tax_fee", "application_fee"]

  defp stripe_amount_cell(cents), do: cents |> StripeAPI.from_stripe_amount() |> amount_cell()

  defp date_cell(nil), do: nil
  defp date_cell(date), do: [{Date.to_erl(date), {0, 0, 0}}, yyyymmdd: true]

  # Elixlsx leaves the workbook's default font unnamed, so viewers fall back to
  # whatever they like (often a serif). Naming it on every cell keeps it plain.
  defp with_basic_font(sheet) do
    %{sheet | rows: Enum.map(sheet.rows, fn row -> Enum.map(row, &basic_font_cell/1) end)}
  end

  defp basic_font_cell(nil), do: nil
  defp basic_font_cell([value | opts]), do: [value, font: "Arial", size: 11] ++ opts
  defp basic_font_cell(value), do: [value, font: "Arial", size: 11]

  defp amount_cell(nil), do: nil
  defp amount_cell(amount), do: [Decimal.to_float(amount), num_format: "0.00"]
end
