defmodule EdenflowersWeb.Gettext do
  @moduledoc """
  Gettext backend for the app. Supports `en`, `sv`, and `fi`, defaulting to `en`.

  See the [Gettext docs](https://hexdocs.pm/gettext) for the translation API.
  """
  use Gettext.Backend, otp_app: :edenflowers, default_locale: "en", locales: ~w(en sv fi)
end
