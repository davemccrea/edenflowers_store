defmodule EdenflowersWeb.Hooks.PutOrder do
  @moduledoc """
  LiveView mount hook that loads the browser's cart into `assigns.order`, or nil until its first add to cart, and
  updates the cart's locale. `assigns.visitor_id` is what opens the cart on that first add.

  A page opened from a code link (`?code=`, put on the cart by `Plugs.ApplyLinkPromotion`) counts the code as
  applied in Umami, like a code typed at checkout.
  """

  use Phoenix.Component

  alias Edenflowers.Orders
  alias EdenflowersWeb.Analytics

  def on_mount(:default, params, %{"visitor_id" => visitor_id} = _session, socket) do
    locale = to_string(Edenflowers.Format.locale())
    actor = socket.assigns[:current_user]
    order = Orders.get_storefront_cart!(visitor_id, actor: actor)

    socket =
      socket
      |> assign(visitor_id: visitor_id, order: order && put_locale(order, locale, actor))
      |> track_link_code(params)

    {:cont, socket}
  end

  defp track_link_code(%{assigns: %{order: %{promotion_code: cart_code}}} = socket, %{"code" => code})
       when is_binary(cart_code) and is_binary(code) do
    if Phoenix.LiveView.connected?(socket) and String.downcase(cart_code) == String.downcase(String.trim(code)),
      do: Analytics.track(socket, "Promo code applied", %{code: code}, once: "promo-link-#{String.downcase(code)}"),
      else: socket
  end

  defp track_link_code(socket, _params), do: socket

  defp put_locale(%{locale: locale} = order, locale, _actor), do: order

  defp put_locale(order, locale, actor) do
    Orders.update_locale(order.id, locale, actor: actor)
    %{order | locale: locale}
  end
end
