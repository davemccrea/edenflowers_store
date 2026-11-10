defmodule Edenflowers.Locales do
  @moduledoc "Single source of truth for supported locales."

  @all ["sv-FI", "fi", "en-GB"]
  @default "sv-FI"
  @translatable_atoms [:"sv-FI", :fi]

  def all, do: @all
  def admin, do: ["sv-FI", "en-GB"]

  def admin_locale(session) do
    locale = session["admin_locale"] || session[Localize.Plug.PutLocale.session_key()]
    if locale in admin(), do: locale, else: @default
  end

  def options, do: Enum.map(@all, &{name(&1), &1})
  def default, do: @default
  def translatable_atoms, do: @translatable_atoms
  def supported?(locale), do: locale in @all

  def name("sv-FI"), do: "Svenska"
  def name("fi"), do: "Suomi"
  def name("en-GB"), do: "English"
end
