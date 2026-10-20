defmodule EdenflowersWeb.LocalizedPaths do
  @moduledoc """
  The public pages that have a URL per language, under /en, /fi and /sv, and
  the same page's URL in another language.

  Path segments are translated in `priv/gettext/<locale>/LC_MESSAGES/routes.po`.
  """
  use EdenflowersWeb, :verified_routes

  alias Edenflowers.Catalog
  alias Edenflowers.Translations
  alias EdenflowersWeb.Courses
  alias EdenflowersWeb.Marketing
  alias EdenflowersWeb.Store

  @locales Enum.map(Edenflowers.Locales.all(), &String.to_atom/1)

  @doc "The page at `path` in `locale`, or nil when `path` isn't a localized page."
  def translate(path, locale) when is_binary(locale), do: translate(path, String.to_existing_atom(locale))

  def translate(path, locale) do
    case Phoenix.Router.route_info(EdenflowersWeb.Router, "GET", path, "") do
      %{phoenix_live_view: {Store.StoreLive, _action, _opts, _live_session}, path_params: %{"category" => slug}} ->
        category_path(slug, path_locale(path), locale)

      %{phoenix_live_view: {view, _action, _opts, _live_session}, path_params: params} ->
        localized_path(locale, view, params)

      _ ->
        nil
    end
  end

  @doc """
  The page at `path` in every language as `{hreflang, path}`, or `[]` when
  `path` isn't a localized page.
  """
  def alternates(path) do
    for locale <- @locales, localized = translate(path, locale), do: {hreflang(locale), localized}
  end

  defp hreflang(locale), do: locale |> to_string() |> String.split("-") |> hd()

  defp path_locale(path) do
    prefix = path |> String.split("/") |> Enum.at(1)
    Enum.find(@locales, &(hreflang(&1) == prefix))
  end

  # Category slugs are translated per category, so the category is found by
  # its slug in the path's language to give its slug in `locale`.
  defp category_path(slug, from_locale, locale) do
    case Catalog.get_category_by_slug(slug, from_locale) do
      {:ok, category} -> path_for(locale, "/#{language}/store/#{Translations.translate(category, locale).slug}")
      {:error, _} -> nil
    end
  end

  defp localized_path(locale, Marketing.HomeLive, _params), do: path_for(locale, "/#{language}")
  defp localized_path(locale, Marketing.WeddingsLive, _params), do: path_for(locale, "/#{language}/weddings")
  defp localized_path(locale, Marketing.CondolencesLive, _params), do: path_for(locale, "/#{language}/condolences")
  defp localized_path(locale, Marketing.AboutLive, _params), do: path_for(locale, "/#{language}/about")
  defp localized_path(locale, Marketing.ContactLive, _params), do: path_for(locale, "/#{language}/contact")
  defp localized_path(locale, Marketing.FaqLive, _params), do: path_for(locale, "/#{language}/faq")

  defp localized_path(locale, Store.StoreLive, _params), do: path_for(locale, "/#{language}/store")
  defp localized_path(locale, Store.ProductLive, %{"id" => id}), do: path_for(locale, "/#{language}/product/#{id}")
  defp localized_path(locale, Courses.CoursesLive, _params), do: path_for(locale, "/#{language}/courses")
  defp localized_path(locale, Courses.CourseLive, %{"id" => id}), do: path_for(locale, "/#{language}/courses/#{id}")
  defp localized_path(_locale, _view, _params), do: nil
end
