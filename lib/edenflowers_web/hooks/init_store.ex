defmodule EdenflowersWeb.Hooks.InitStore do
  use EdenflowersWeb, :live_view
  alias Edenflowers.Store.Order

  def on_mount(:put_locale, _params, %{"cldr_locale" => cldr_locale} = _session, socket) do
    {:ok, language_tag} = Edenflowers.Cldr.put_locale(cldr_locale)
    Edenflowers.Cldr.put_gettext_locale(language_tag)
    {:cont, socket}
  end

  def on_mount(:put_order, _params, %{"order_id" => order_id} = _session, socket) do
    order = Order.get_order_for_checkout!(order_id)
    {:cont, socket |> assign(order: order)}
  end
end
