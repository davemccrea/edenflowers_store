defmodule Edenflowers.Expressions.HelsinkiToday do
  @moduledoc """
  `helsinki_today()` in an Ash expression: `Edenflowers.ShopTime.today/0`. Ash's
  own `today()` is UTC's date, which lags Helsinki's for two or three hours after
  midnight.
  """
  use Ash.CustomExpression, name: :helsinki_today, arguments: [[]]

  # Evaluated when the query is built, so an expression and Elixir code agree.
  def expression(_data_layer, []), do: {:ok, Edenflowers.ShopTime.today()}
end
