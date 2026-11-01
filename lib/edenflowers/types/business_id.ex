defmodule Edenflowers.Types.BusinessId do
  @moduledoc """
  A Finnish Y-tunnus (business ID), such as 2944459-6: seven digits, a hyphen
  and a check digit. The check digit is 11 minus the remainder of the digits
  weighted 7, 9, 10, 5, 8, 4, 2 divided by 11, or 0 when there is no
  remainder. A remainder of 1 is never issued, so no check digit matches it.
  """
  use Ash.Type.NewType, subtype_of: :string, constraints: [trim?: true]

  @weights [7, 9, 10, 5, 8, 4, 2]

  @impl Ash.Type
  def apply_constraints(nil, _constraints), do: {:ok, nil}

  def apply_constraints(value, constraints) do
    with {:ok, value} <- Ash.Type.apply_constraints(:string, value, subtype_constraints(constraints)) do
      if valid?(value), do: {:ok, value}, else: {:error, message: "Must be a valid Y-tunnus, such as 1234567-8"}
    end
  end

  defp valid?(value) do
    case Regex.run(~r/^(\d{7})-(\d)$/, value, capture: :all_but_first) do
      [digits, check] -> check_digit(digits) == String.to_integer(check)
      nil -> false
    end
  end

  defp check_digit(digits) do
    sum =
      digits
      |> String.graphemes()
      |> Enum.map(&String.to_integer/1)
      |> Enum.zip_with(@weights, &(&1 * &2))
      |> Enum.sum()

    case rem(sum, 11) do
      0 -> 0
      remainder -> 11 - remainder
    end
  end
end
