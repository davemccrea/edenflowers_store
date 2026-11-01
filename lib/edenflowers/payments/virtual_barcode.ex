defmodule Edenflowers.Payments.VirtualBarcode do
  @moduledoc """
  The virtuaaliviivakoodi printed on an invoice: the 54 digits a payer pastes
  into their bank, or scans as the Code 128 bar code that encodes them, to
  fill in the account, amount, viitenumero and due date at once.

  Version 4 of Finance Finland's Bank Bar Code Guide (5.3), for an FI IBAN
  and a national viitenumero: the version digit 4, the IBAN's 16 digits, the
  amount as 6 digits of euros and 2 of cents, three reserved zeros, the
  viitenumero padded to 20 digits, and the due date as YYMMDD. Code 128's own
  start, check and stop characters are added by whatever prints the bar code.
  """

  @max_cents 99_999_999

  @doc """
  The 54 digits for paying `amount` euros to `iban` with `reference` by
  `due_date`. The IBAN may be spaced. Raises for an IBAN that isn't Finnish
  or an amount of a million euros or more, which the code can't carry.
  """
  def version_4(iban, amount, reference, %Date{} = due_date) do
    "FI" <> account = String.replace(iban, " ", "")
    cents = amount |> Decimal.mult(100) |> Decimal.round() |> Decimal.to_integer()

    unless String.match?(account, ~r/^\d{16}$/), do: raise(ArgumentError, "not a Finnish IBAN: #{iban}")
    unless cents in 0..@max_cents, do: raise(ArgumentError, "amount out of range: #{amount}")

    "4" <>
      account <>
      pad(cents, 8) <>
      "000" <>
      pad(reference, 20) <>
      Calendar.strftime(due_date, "%y%m%d")
  end

  defp pad(value, length), do: value |> to_string() |> String.pad_leading(length, "0")
end
