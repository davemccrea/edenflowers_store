defmodule Edenflowers.Pricing.Vat do
  @moduledoc """
  The one rule for taking VAT out of a VAT-inclusive amount, shared by
  orders, course bookings, invoices and the monthly report.
  """

  @doc """
  The taxable base in a tax-inclusive amount, rounded to cents. `rate` is a
  fraction, 0.255 for 25,5 %. VAT is taken as the remainder so base + VAT
  always equals the gross.
  """
  def net_of_vat(gross, rate), do: gross |> Decimal.div(Decimal.add(1, rate)) |> Decimal.round(2)
end
