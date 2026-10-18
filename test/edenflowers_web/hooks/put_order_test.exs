defmodule EdenflowersWeb.Hooks.PutOrderTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  # The first request runs InitStore with the cart still readable, so the
  # later live/2 only does the connected mount, like a reconnecting tab.
  setup %{conn: conn} do
    order = generate(order())
    conn = conn |> Plug.Test.init_test_session(%{order_id: order.id}) |> get(~p"/about")
    %{conn: conn, order: order}
  end

  test "redirects to the same page when the session cart has been purged", %{conn: conn, order: order} do
    Ash.destroy!(order, action: :purge_abandoned_cart, authorize?: false)

    assert {:error, {:redirect, %{to: "/about"}}} = live(conn)
  end

  test "redirects when a guest's session order has been placed", %{conn: conn, order: order} do
    Ash.Seed.update!(order, %{state: :placed})

    assert {:error, {:redirect, %{to: "/about"}}} = live(conn)
  end

  test "mounts with a valid cart", %{conn: conn, order: order} do
    {:ok, view, _html} = live(conn)
    assert :sys.get_state(view.pid).socket.assigns.order.id == order.id
  end
end
