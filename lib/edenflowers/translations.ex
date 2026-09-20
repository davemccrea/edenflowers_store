defmodule Edenflowers.Translations do
  @moduledoc """
  Applies `AshTranslation` translations for the current request locale.

  Translatable resources keep the default locale (`en-GB`) on the attribute
  itself and store the other locales in a `:translations` map, so an
  untranslated record falls back to English rather than rendering blank.

  Always go through `translate/1` at the point records are loaded — calling a
  translatable field without it silently renders the default locale instead of
  raising, which is easy to miss in review.
  """

  @doc "Translate a record, a list of records, or nil into the current locale."
  def translate(data), do: translate(data, Edenflowers.Format.locale())

  @doc "Translate into an explicit locale."
  def translate(nil, _locale), do: nil

  def translate([], _locale), do: []

  def translate(data, locale) when is_list(data) do
    data
    |> Ash.load!(:translations)
    |> Enum.map(&AshTranslation.translate(&1, locale))
  end

  def translate(data, locale) do
    data
    |> Ash.load!(:translations)
    |> AshTranslation.translate(locale)
  end

  @doc """
  Translate a loaded belongs_to on each record, e.g. `translate_assoc(variants, :product)`.

  Loads translations for the whole batch in one query rather than per record.
  """
  def translate_assoc(records, key) when is_list(records),
    do: translate_assoc(records, key, Edenflowers.Format.locale())

  @doc "Translate a loaded belongs_to into an explicit locale."
  def translate_assoc(records, key, locale) when is_list(records) do
    translated = records |> Enum.map(&Map.fetch!(&1, key)) |> translate(locale)
    Enum.zip_with(records, translated, &Map.put(&1, key, &2))
  end
end
