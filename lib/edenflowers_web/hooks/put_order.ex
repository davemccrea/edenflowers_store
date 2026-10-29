defmodule EdenflowersWeb.Hooks.PutOrder do
  @moduledoc """
  LiveView mount hook that loads the session cart into `assigns.order` and updates its locale. A stale cart triggers a fresh HTTP request.
  """

  use Phoenix.Component

  alias Edenflowers.Orders

  def on_mount(:default, _params, %{"order_id" => order_id} = _session, socket) do
    locale = to_string(Edenflowers.Format.locale())
    actor = socket.assigns[:current_user]

    case Orders.get_order_for_storefront(order_id, actor: actor) do
      {:ok, order} ->
        {:cont, assign(socket, order: put_locale(order, locale, actor))}

      # InitStore only checks the session cart on HTTP requests, so a tab that
      # reconnects after the cart was purged or placed elsewhere lands here.
      # Reloading over HTTP lets InitStore start a new cart.
      {:error, %Ash.Error.Invalid{}} ->
        uri = Phoenix.LiveView.get_connect_info(socket, :uri)
        to = if uri.query in [nil, ""], do: uri.path, else: "#{uri.path}?#{uri.query}"
        {:halt, Phoenix.LiveView.redirect(socket, to: to)}
    end
  end

  defp put_locale(%{locale: locale} = order, locale, _actor), do: order

  defp put_locale(order, locale, actor) do
    Orders.update_locale(order.id, locale, actor: actor)
    %{order | locale: locale}
  end
end
