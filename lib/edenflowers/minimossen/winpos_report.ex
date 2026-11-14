defmodule Edenflowers.Minimossen.WinposReport do
  @moduledoc """
  Reads a weekly "Tuoteryhmät" report from Minimossen's Winpos till: the week it
  covers and each product group's gross sales. Anything that doesn't match the
  report's layout is an error, so a changed report is never half read.
  """

  @period ~r/^Pvm: (\d{1,2})\.(\d{1,2})\.(\d{4}) - (\d{1,2})\.(\d{1,2})\.(\d{4})$/

  @doc """
  Returns `{:ok, %{week_start: monday, groups: [%{code: "3", name: "Eden Flowers kukat", gross: Decimal}]}}`.
  """
  def parse(xls) do
    with {:ok, rows} <- read(xls),
         {:ok, week_start} <- week_start(rows),
         {:ok, groups} <- groups(rows) do
      {:ok, %{week_start: week_start, groups: groups}}
    end
  end

  defp read(xls) do
    case Spreadsheet.parse(xls, sheet: "Sheet1", format: :binary) do
      {:ok, rows} -> {:ok, rows}
      {:error, reason} -> {:error, {:winpos_report_unreadable, reason}}
    end
  end

  defp week_start(rows) do
    case Enum.find_value(rows, &period(List.first(&1))) do
      nil ->
        {:error, :winpos_report_period_missing}

      {from, to} ->
        if Date.day_of_week(from) == 1 and Date.diff(to, from) == 6,
          do: {:ok, from},
          else: {:error, {:winpos_report_not_a_week, from, to}}
    end
  end

  defp period(cell) when is_binary(cell) do
    with [_match | parts] <- Regex.run(@period, String.trim(cell)),
         [from_day, from_month, from_year, to_day, to_month, to_year] = Enum.map(parts, &String.to_integer/1),
         {:ok, from} <- Date.new(from_year, from_month, from_day),
         {:ok, to} <- Date.new(to_year, to_month, to_day) do
      {from, to}
    else
      _no_period -> nil
    end
  end

  defp period(_cell), do: nil

  # The groups sit between the "Koodi" header and the "Yhteensä" total, which must add up.
  defp groups(rows) do
    with [header | rest] <- Enum.drop_while(rows, &(List.first(&1) != "Koodi")),
         {lines, [total_row | _after]} <- Enum.split_while(rest, &(List.first(&1) != "Yhteensä")),
         {:ok, columns} <- columns(header),
         {:ok, groups} <- group_lines(lines, columns),
         {:ok, total} <- amount(Enum.at(total_row, columns.gross)) do
      sum = Enum.reduce(groups, Decimal.new(0), &Decimal.add(&1.gross, &2))
      if Decimal.equal?(sum, total), do: {:ok, groups}, else: {:error, {:winpos_report_total_mismatch, sum, total}}
    else
      {:error, error} -> {:error, error}
      _no_table -> {:error, :winpos_report_table_missing}
    end
  end

  defp columns(header) do
    case Enum.map(["Koodi", "Nimitys", "Myynti"], fn name -> Enum.find_index(header, &(&1 == name)) end) do
      [code, name, gross] when is_integer(code) and is_integer(name) and is_integer(gross) ->
        {:ok, %{code: code, name: name, gross: gross}}

      _missing ->
        {:error, {:winpos_report_columns_missing, header}}
    end
  end

  defp group_lines(lines, columns) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, groups} ->
      code = Enum.at(line, columns.code)
      name = Enum.at(line, columns.name)

      with true <- is_binary(code) and code != "" and is_binary(name),
           {:ok, gross} <- amount(Enum.at(line, columns.gross)) do
        {:cont, {:ok, groups ++ [%{code: code, name: name, gross: gross}]}}
      else
        _bad_line -> {:halt, {:error, {:winpos_report_bad_line, line}}}
      end
    end)
  end

  defp amount(value) when is_float(value), do: {:ok, value |> Decimal.from_float() |> Decimal.round(2)}
  defp amount(value) when is_integer(value), do: {:ok, Decimal.new(value)}
  defp amount(value), do: {:error, {:winpos_report_bad_amount, value}}
end
