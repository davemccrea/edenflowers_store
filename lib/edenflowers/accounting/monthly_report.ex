defmodule Edenflowers.Accounting.MonthlyReport do
  @moduledoc """
  Builds the zip Jennie sends her accountant each month: a spreadsheet of the
  month's expenses and every receipt PDF behind them, in Swedish.

  VAT is reported on a cash basis, so an expense counts in the month it was
  paid: its `paid_on`, or its `date` when that's empty.
  """
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [context: "accounting report"]

  require Ash.Query

  alias Edenflowers.Expenses.Expense
  alias Edenflowers.External.PapraAPI
  alias EdenflowersWeb.Admin.Components
  alias Elixlsx.Sheet
  alias Elixlsx.Workbook

  def build(year, month) do
    Gettext.with_locale(EdenflowersWeb.Gettext, "sv", fn ->
      first = Date.new!(year, month, 1)
      label = first |> Date.to_iso8601() |> String.slice(0, 7)
      spreadsheet = "rapport-#{label}.xlsx"

      with {:ok, expenses} <- paid_expenses(first, Date.end_of_month(first)),
           rows = expenses |> Enum.with_index(1) |> Enum.map(fn {e, n} -> {n, e, receipt_name(n, e)} end),
           {:ok, receipts} <- fetch_receipts(rows),
           workbook = %Workbook{sheets: [expenses_sheet(rows)]},
           {:ok, {_, xlsx}} <- Elixlsx.write_to_memory(workbook, spreadsheet),
           files = [{~c"#{spreadsheet}", xlsx} | receipts],
           {:ok, {_, zip}} <- :zip.create(~c"redovisning-#{label}.zip", files, [:memory]) do
        {:ok, "redovisning-#{label}.zip", zip}
      end
    end)
  end

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

  # Any failure fails the whole report, so the accountant never gets a zip with receipts missing.
  defp fetch_receipts(rows) do
    organization_id = Application.get_env(:edenflowers, :papra_organization_id)

    Enum.reduce_while(rows, {:ok, []}, fn {_n, expense, name}, {:ok, files} ->
      case PapraAPI.impl().fetch_document(organization_id, expense.document_id) do
        {:ok, %{body: body}} -> {:cont, {:ok, [{~c"kvitton/#{name}", body} | files]}}
        {:error, error} -> {:halt, {:error, {:receipt_fetch_failed, expense.document_id, error}}}
      end
    end)
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

  defp expense_row({n, expense, receipt}) do
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
      receipt
    ]
  end

  defp currency_totals(rows) do
    rows
    |> Enum.map(fn {_n, expense, _receipt} -> expense end)
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

  defp date_cell(nil), do: nil
  defp date_cell(date), do: [{Date.to_erl(date), {0, 0, 0}}, yyyymmdd: true]

  defp amount_cell(nil), do: nil
  defp amount_cell(amount), do: [Decimal.to_float(amount), num_format: "0.00"]
end
