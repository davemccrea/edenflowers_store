defmodule Edenflowers.Types.Price do
  @moduledoc """
  Accepts euro amounts typed with either a decimal comma or a dot and rounds
  string input to cents.
  """
  use Ash.Type.NewType, subtype_of: :decimal

  @impl Ash.Type
  def cast_input(value, constraints) when is_binary(value) do
    case value |> String.trim() |> String.replace(",", ".") do
      "" ->
        {:ok, nil}

      value ->
        case Decimal.parse(value) do
          {price, ""} -> super(Decimal.round(price, 2), constraints)
          _ -> {:error, message: "enter a price"}
        end
    end
  end

  def cast_input(value, constraints), do: super(value, constraints)
end
