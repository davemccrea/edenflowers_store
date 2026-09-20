defmodule EdenflowersWeb.Gettext do
  @moduledoc """
  Gettext backend for the app. Supports `en`, `sv`, and `fi`, defaulting to `en`.

  See the [Gettext docs](https://hexdocs.pm/gettext) for the translation API.
  """
  use Gettext.Backend, otp_app: :edenflowers, default_locale: "en", locales: ~w(en sv fi)

  require Logger

  @doc """
  Runs `fun` with the Gettext locale that best matches `app_locale`.

  App locales are region-qualified ("sv-FI") but the catalogs are two-letter
  ("sv"), so this resolves via CLDR best-match rather than handing the raw
  locale to Gettext (which would fall back to English). Unknown locales fall
  back to the default.
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
