defmodule EdenflowersWeb.DatePicker.Keymap do
  @moduledoc """
  WAI-ARIA date-picker keyboard navigation.

  Maps a key event on a focused date to the date that should receive focus
  next. Past months are clamped: any navigation that would move focus before
  the first of the current month is suppressed (focus stays put).

  See https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/examples/datepicker-dialog/
  """

  require Logger

  @week_begins :default

  @doc """
  Returns the date that should receive focus after `key` is pressed on `from`.

  Unknown keys return `from` unchanged.
  """
  @spec next_date(Date.t(), String.t(), Date.t()) :: Date.t()
  def next_date(from, key, today) do
    from
    |> shift(key)
    |> clamp_to_current_month(from, today)
  end

  defp shift(date, "ArrowUp"), do: Date.add(date, -7)
  defp shift(date, "ArrowDown"), do: Date.add(date, 7)
  defp shift(date, "ArrowLeft"), do: Date.add(date, -1)
  defp shift(date, "ArrowRight"), do: Date.add(date, 1)
  defp shift(date, "PageUp"), do: Date.shift(date, month: -1)
  defp shift(date, "PageDown"), do: Date.shift(date, month: 1)
  defp shift(date, "Home"), do: Date.beginning_of_week(date, @week_begins)
  defp shift(date, "End"), do: Date.end_of_week(date, @week_begins)

  defp shift(date, key) do
    Logger.info("key #{key} not configured")
    date
  end

  defp clamp_to_current_month(target, from, today) do
    if Date.before?(target, Date.beginning_of_month(today)), do: from, else: target
  end
end
