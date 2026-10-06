defmodule Edenflowers.Locales do
  @moduledoc "Single source of truth for supported locales."

  @all ["en-GB", "sv-FI", "fi"]
  @default "en-GB"
  @translatable_atoms [:"sv-FI", :fi]

  def all, do: @all
  def default, do: @default
  def translatable_atoms, do: @translatable_atoms
  def supported?(locale), do: locale in @all

  def name("sv-FI"), do: "Svenska"
  def name("fi"), do: "Suomi"
  def name("en-GB"), do: "English"
end
