defmodule Edenflowers.Types.DecimalComma do
  @moduledoc """
  Accepts decimal input with either a comma or a dot as the decimal separator,
  preserving the entered precision. Use `Edenflowers.Types.Price` for euro
  amounts that should be rounded to cents instead.
  """
  use Ash.Type.NewType, subtype_of: :decimal

  @impl Ash.Type
  def cast_input(value, constraints) when is_binary(value) do
    case value |> String.trim() |> String.replace(",", ".") do
      "" ->
        {:ok, nil}

      value ->
        case Decimal.parse(value) do
          {%Decimal{coef: coef} = number, ""} when is_integer(coef) -> super(number, constraints)
          _ -> {:error, message: "is invalid"}
        end
    end
  end

  def cast_input(value, constraints), do: super(value, constraints)
end
