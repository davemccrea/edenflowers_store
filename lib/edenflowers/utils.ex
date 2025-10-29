defmodule Edenflowers.Utils do
  @spec format_money(number() | nil) :: String.t()
  def format_money(nil), do: format_money(0)

  def format_money(value) do
    Cldr.Number.to_string!(value,
      format: :currency,
      currency: "EUR",
      locale: Cldr.get_locale()
    )
  end

  @spec truncate(binary() | nil, non_neg_integer()) :: binary()
  def truncate(nil, _max_length), do: ""
  def truncate(text, max_length) when max_length <= 3, do: String.slice(to_string(text), 0, max_length)

  def truncate(text, max_length) when is_binary(text) and is_integer(max_length) do
    trimmed = String.trim(text)

    if String.length(trimmed) <= max_length do
      trimmed
    else
      trimmed
      |> String.slice(0, max_length - 3)
      |> String.replace(~r/\s+\S*$/, "")
      |> String.trim_trailing()
      |> Kernel.<>("...")
    end
  end
end
