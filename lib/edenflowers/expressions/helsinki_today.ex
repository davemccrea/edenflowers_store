defmodule Edenflowers.Expressions.HelsinkiToday do
  @moduledoc """
  Today's date in Helsinki, where the shop's days begin and end: `helsinki_today()`
  in an Ash expression, `today/0` in Elixir. Ash's own `today()` is UTC's date,
  which lags Helsinki's for two or three hours after midnight.
  """
  use Ash.CustomExpression, name: :helsinki_today, arguments: [[]]

  # Evaluated when the query is built, so an expression and Elixir code agree.
  def expression(_data_layer, []), do: {:ok, today()}

  def today(now \\ DateTime.utc_now()) do
    now |> DateTime.shift_zone!("Europe/Helsinki") |> DateTime.to_date()
  end
end
