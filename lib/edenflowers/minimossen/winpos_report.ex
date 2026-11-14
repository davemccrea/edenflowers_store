defmodule Edenflowers.Minimossen.WinposReport do
  @moduledoc """
  Reads a weekly "Tuoteryhmät" report from Minimossen's Winpos till: the week it
  covers and each product group's gross sales. Anything that doesn't match the
  report's layout is an error, so a changed report is never half read.
  """

  @period ~r/^Pvm: (\d{1,2})\.(\d{1,2})\.(\d{4}) - (\d{1,2})\.(\d{1,2})\.(\d{4})$/

  @covered ~r/^Tuoteryhmät: (.+)$/

  @doc """
  Returns `{:ok, %{week_start: monday, groups: [%{code: "3", name: "Eden Flowers kukat", gross: Decimal}]}}`.

  Every group the report covers is in `groups`. One without sales that week has no line
  in the report, so it reads 0 and is named by its code.
  """
  def parse(xls) do
    with {:ok, rows} <- read(xls), do: from_rows(rows)
  end

  @doc "Reads the rows of a report's sheet, as `parse/1` does."
  def from_rows(rows) do
    with {:ok, week_start} <- week_start(rows),
         {:ok, covered} <- covered_codes(rows),
         {:ok, groups} <- groups(rows) do
      {:ok, %{week_start: week_start, groups: groups ++ unsold(covered, groups)}}
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

  # The report's filter cells name the groups it covers, e.g. "Tuoteryhmät: 66" and
  # "Tuoteryhmät: 6 - 7", a range of codes.
  defp covered_codes(rows) do
    filters = for row <- rows, cell <- row, is_binary(cell), [_match, filter] <- [Regex.run(@covered, cell)], do: filter

    codes =
      Enum.flat_map(filters, fn filter ->
        case filter |> String.split("-") |> Enum.map(&Integer.parse(String.trim(&1))) do
          [{code, ""}] -> [code]
          [{from, ""}, {to, ""}] when from <= to -> Enum.to_list(from..to)
          _other -> [:bad]
        end
      end)

    cond do
      codes == [] -> {:error, :winpos_report_groups_missing}
      :bad in codes -> {:error, {:winpos_report_bad_groups, filters}}
      true -> {:ok, codes |> Enum.map(&Integer.to_string/1) |> Enum.uniq()}
    end
  end

  defp unsold(covered, groups) do
    sold = MapSet.new(groups, & &1.code)
    for code <- covered, code not in sold, do: %{code: code, name: code, gross: Decimal.new("0.00")}
  end

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
