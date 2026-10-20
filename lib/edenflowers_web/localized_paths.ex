defmodule EdenflowersWeb.LocalizedPaths do
  @moduledoc """
  The same public page in every language, under /en, /fi and /sv, as a map of
  locale code to path. Pages assign it as `:alternates` for the hreflang links
  and the language switcher.

  Path segments are translated in `priv/gettext/<locale>/LC_MESSAGES/routes.po`.
  """
  use Localize.VerifiedRoutes,
    endpoint: EdenflowersWeb.Endpoint,
    router: EdenflowersWeb.Router,
    gettext: EdenflowersWeb.Gettext

  @doc ~S'Builds the alternates for a `~q`-style route, e.g. `alternates("/#{language}/about")`.'
  defmacro alternates(route) do
    quote do
      Map.new(Edenflowers.Locales.all(), fn code ->
        {code, Localize.VerifiedRoutes.path_for(String.to_existing_atom(code), unquote(route))}
      end)
    end
  end

  @doc "The store's URL in `locale`, for emails, which aren't rendered in a request's locale."
  def store_url(locale), do: url_for(locale, "/#{language}/store")

  @doc "A store category's alternates, from the untranslated category, whose slug differs per language."
  def category_alternates(category) do
    Map.new(Edenflowers.Locales.all(), fn code ->
      locale = String.to_existing_atom(code)
      slug = AshTranslation.translate(category, locale).slug
      {code, path_for(locale, "/#{language}/store/#{slug}")}
    end)
  end
end
