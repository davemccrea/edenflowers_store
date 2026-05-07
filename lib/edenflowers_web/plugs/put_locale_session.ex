defmodule EdenflowersWeb.Plugs.PutLocaleSession do
  @moduledoc """
  Persists the locale resolved by `Localize.Plug.PutLocale` to the session
  as a plain string. Uses `cldr_locale_id` (the resolved supported locale)
  rather than `canonical_locale_id` (the input form), so a request with an
  unsupported `Accept-Language` lands on its supported fallback in the
  session, not the rejected input.
  """
  import Plug.Conn

  @session_key Localize.Plug.PutLocale.session_key()

  def init(opts), do: opts

  def call(conn, _opts) do
    case Localize.Plug.PutLocale.get_locale(conn) do
      %Localize.LanguageTag{cldr_locale_id: id} when not is_nil(id) ->
        put_session(conn, @session_key, to_string(id))

      _ ->
        conn
    end
  end
end
