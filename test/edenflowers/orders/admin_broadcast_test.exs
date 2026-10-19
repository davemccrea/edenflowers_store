defmodule Edenflowers.Orders.AdminBroadcastTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Orders

  # admin:orders is shared with every async test, so each test matches its own order.
  setup do
    EdenflowersWeb.Endpoint.subscribe("admin:orders")
    :ok
  end

  test "any change to a placed order refreshes the admin pages showing it" do
    %{id: id} = order = placed_order()
    EdenflowersWeb.Endpoint.subscribe("order:changed:#{order.id}")

    {:ok, _order} = Orders.update_florist_note(order, %{florist_note: "White only"}, actor: generate(admin_user()))

    assert_receive %Phoenix.Socket.Broadcast{topic: "admin:orders", payload: %{data: %{id: ^id}}}
    assert_receive %Phoenix.Socket.Broadcast{topic: "order:changed:" <> _, event: "update_florist_note"}
  end

  test "a cart's checkout steps don't" do
    %{id: id} = cart = generate(order())

    {:ok, _cart} = Orders.update_locale(cart, "fi", authorize?: false)

    refute_receive %Phoenix.Socket.Broadcast{topic: "admin:orders", payload: %{data: %{id: ^id}}}
  end
end
