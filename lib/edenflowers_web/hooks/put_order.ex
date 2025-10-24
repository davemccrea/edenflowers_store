defmodule EdenflowersWeb.Hooks.PutOrder do
  use Phoenix.Component
  alias Edenflowers.Store.Order

  def on_mount(:default, _params, %{"order_id" => order_id} = _session, socket) do
    locale = Edenflowers.Cldr.get_locale() |> Cldr.to_string()

    case Order.update_locale_get_for_checkout(order_id, locale) do
      {:ok, order} ->
        {:cont, assign(socket, order: order)}

      # TODO: handle error
      {:error, _} ->
        {:halt, socket}
    end
  end
end
