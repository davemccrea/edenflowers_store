defmodule Edenflowers.ShopTime do
  @moduledoc """
  The shop's clock. Its days begin and end in Helsinki, so "today" and "now" are
  Helsinki's, not UTC's. Ash expressions read the same date via `helsinki_today()`.
  """

  @timezone "Europe/Helsinki"

  def timezone, do: @timezone

  def now, do: DateTime.now!(@timezone)

  def today(now \\ DateTime.utc_now()) do
    now |> DateTime.shift_zone!(@timezone) |> DateTime.to_date()
  end
end
