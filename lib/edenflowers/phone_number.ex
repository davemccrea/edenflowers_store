defmodule Edenflowers.PhoneNumber do
  @moduledoc """
  Parses phone numbers as customers type them. A number without a country
  code is read as Finnish. Finnish numbers display in the national format
  customers know ("045 1505141"), foreign ones in international format
  ("+46 70 123 45 67").
  """

  @default_region "FI"
  @finland_country_code 358

  @spec format(String.t() | nil, :display | :e164) :: {:ok, String.t()} | :error
  def format(input, format \\ :display)

  def format(input, format) when is_binary(input) do
    with {:ok, number} <- ExPhoneNumber.parse(input, @default_region),
         true <- ExPhoneNumber.is_valid_number?(number) do
      {:ok, ExPhoneNumber.format(number, library_format(number, format))}
    else
      _ -> :error
    end
  end

  def format(_input, _format), do: :error

  defp library_format(_number, :e164), do: :e164
  defp library_format(%{country_code: @finland_country_code}, :display), do: :national
  defp library_format(_number, :display), do: :international
end
