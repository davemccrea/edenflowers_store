defmodule Edenflowers.Payments.ReferenceNumber do
  @moduledoc """
  The Finnish reference number (viitenumero) a customer types into their bank
  when paying an invoice: the invoice number followed by a check digit. The
  digits are weighted 7, 3, 1, 7, 3, 1… from the right; the check digit takes
  their sum up to the next multiple of ten. Finance Finland's "Forming a
  Finnish reference number" (2009) sets the rules: at least three digits
  before the check digit, at most 19, and no leading zeros. So an invoice
  number needs three to nineteen digits.
  """

  @weights [7, 3, 1]

  @doc "The reference number for an invoice number, as unspaced digits."
  def from_invoice_number(number) when is_integer(number) and number in 100..9_999_999_999_999_999_999 do
    base = Integer.to_string(number)
    base <> Integer.to_string(check_digit(base))
  end

  @doc "Whether a reference number has a valid length, no leading zero, and its check digit last."
  def valid?(reference) do
    with true <- Regex.match?(~r/^[1-9]\d{3,19}$/, reference),
         {base, check} <- String.split_at(reference, -1) do
      check_digit(base) == String.to_integer(check)
    end
  end

  @doc "Groups a reference number in fives from the right, as banks print it: 1 23453."
  def format(reference) do
    reference
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(5)
    |> Enum.map_join(" ", &Enum.join/1)
    |> String.reverse()
  end

  defp check_digit(base) do
    sum =
      base
      |> String.reverse()
      |> String.graphemes()
      |> Enum.map(&String.to_integer/1)
      |> Enum.zip_with(Stream.cycle(@weights), &(&1 * &2))
      |> Enum.sum()

    rem(10 - rem(sum, 10), 10)
  end
end
