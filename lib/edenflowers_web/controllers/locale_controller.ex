defmodule EdenflowersWeb.LocaleController do
  use EdenflowersWeb, :controller

  def index(conn, %{"cldr_locale" => cldr_locale} = _params) do
    conn
    |> put_session("cldr_locale", cldr_locale)
    # TODO: redirect to the same page
    |> redirect(to: ~p"/")
  end
end
