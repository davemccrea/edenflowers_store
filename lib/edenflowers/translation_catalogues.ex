defmodule Edenflowers.TranslationCatalogues do
  @moduledoc "Supported catalogue languages by audience. English uses source text."

  def locales("admin"), do: ~w(en sv)
  def locales("cinder"), do: ~w(sv)
  def locales(_domain), do: ~w(en sv fi)
end
