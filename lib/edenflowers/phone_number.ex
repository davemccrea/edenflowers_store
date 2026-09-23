defmodule Edenflowers.PhoneNumber do
  @moduledoc """
  Parses phone numbers as customers type them. A number without a country
  code is read as Finnish, so "040 123 4567" becomes "+358 40 1234567".
  """

  @default_region "FI"

  @spec format(String.t() | nil, :international | :e164) :: {:ok, String.t()} | :error
  def format(input, format \\ :international)

  def format(input, format) when is_binary(input) do
    with {:ok, number} <- ExPhoneNumber.parse(input, @default_region),
         true <- ExPhoneNumber.is_valid_number?(number) do
      {:ok, ExPhoneNumber.format(number, format)}
    else
      _ -> :error
    end
  end

  def format(_input, _format), do: :error
end
