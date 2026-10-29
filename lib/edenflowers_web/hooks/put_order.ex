defmodule EdenflowersWeb.Hooks.PutOrder do
  @moduledoc """
  LiveView mount hook that loads the browser's cart into `assigns.order`, or nil until its first add to cart, and
  updates the cart's locale. `assigns.visitor_id` is what opens the cart on that first add.
  """

  use Phoenix.Component

  alias Edenflowers.Orders

  def on_mount(:default, _params, %{"visitor_id" => visitor_id} = _session, socket) do
    locale = to_string(Edenflowers.Format.locale())
    actor = socket.assigns[:current_user]
    order = Orders.get_storefront_cart!(visitor_id, actor: actor)

    {:cont, assign(socket, visitor_id: visitor_id, order: order && put_locale(order, locale, actor))}
  end

  defp put_locale(%{locale: locale} = order, locale, _actor), do: order

  defp put_locale(order, locale, actor) do
    Orders.update_locale(order.id, locale, actor: actor)
    %{order | locale: locale}
  end
end
