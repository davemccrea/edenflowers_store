defmodule EdenflowersWeb.Hooks.PutOrder do
  use Phoenix.Component

  alias Edenflowers.Orders

  def on_mount(:default, _params, %{"order_id" => order_id} = _session, socket) do
    locale = to_string(Edenflowers.Format.locale())
    actor = socket.assigns[:current_user]

    order =
      order_id
      |> Orders.get_order_for_checkout!(actor: actor)
      |> put_locale(locale, actor)

    {:cont, assign(socket, order: order)}
  end

  defp put_locale(%{locale: locale} = order, locale, _actor), do: order

  defp put_locale(order, locale, actor) do
    Orders.update_locale(order.id, locale, actor: actor)
    %{order | locale: locale}
  end
end
