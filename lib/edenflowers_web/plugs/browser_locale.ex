defmodule EdenflowersWeb.Plugs.BrowserLocale do
  @moduledoc """
  The locale for a browser that named no language the shop speaks.

  `Localize.Plug.PutLocale` falls through to this when its `:default`, since
  `Localize.AcceptLanguage` skips a header tag that matches no supported
  locale. A browser that asked for a language we do not have reads English,
  the international default, where one that sent no header at all gets the
  shop's own default.
  """

  @doc false
  def fallback(conn, _options) do
    case Plug.Conn.get_req_header(conn, "accept-language") do
      [] -> Localize.validate_locale(Edenflowers.Locales.default())
      _header -> {:ok, Localize.default_locale()}
    end
  end
end
