defmodule Edenflowers.Types.DecimalComma do
  @moduledoc """
  A decimal number typed the Finnish way too, with a decimal comma, kept as
  precise as it was typed. `Edenflowers.Types.Price` is the one for euros,
  rounded to cents.
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
