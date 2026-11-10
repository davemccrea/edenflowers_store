defmodule EdenflowersWeb.Plugs.PutAdminLocale do
  @moduledoc "Sets the admin interface locale without changing the storefront preference."
  import Plug.Conn

  alias Localize.Plug.PutLocale

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = Edenflowers.Locales.admin_locale(get_session(conn))

    PutLocale.call(
      conn,
      PutLocale.init(from: [], default: locale, gettext: EdenflowersWeb.Gettext)
    )
  end
end
