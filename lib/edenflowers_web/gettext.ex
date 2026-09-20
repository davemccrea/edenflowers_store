defmodule EdenflowersWeb.Gettext do
  @moduledoc """
  Gettext backend for the app. Supports `en`, `sv`, and `fi`, defaulting to `en`.

  See the [Gettext docs](https://hexdocs.pm/gettext) for the translation API.
  """
  use Gettext.Backend, otp_app: :edenflowers, default_locale: "en", locales: ~w(en sv fi)

  require Logger

  @doc """
  Runs `fun` with this backend's locale set to the Gettext locale that best
  matches an app locale.

  `order.locale` and friends are region-qualified (e.g. "sv-FI"), but the PO
  catalogs are two-letter ("sv"). `Localize.Locale.gettext_locale_id/2` resolves
  the former to the latter via CLDR best-match, so callers don't silently fall
  back to English for a locale that does have a catalog. Unknown locales fall
  back to the current (default) locale, matching `Localize.Plug`'s behaviour.
  """
  def with_app_locale(app_locale, fun) when is_function(fun, 0) do
    gettext_locale =
      case Localize.Locale.gettext_locale_id(app_locale, __MODULE__) do
        {:ok, locale} ->
          locale

        {:error, _} ->
          Logger.warning("No Gettext catalog for locale #{inspect(app_locale)}; using default")
          Gettext.get_locale(__MODULE__)
      end

    Gettext.with_locale(__MODULE__, gettext_locale, fun)
  end
end
