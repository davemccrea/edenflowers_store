defmodule EdenflowersWeb.Hooks.HandleLineItemChangedTest do
  @moduledoc """
  Integration coverage for the cart-drawer-from-non-checkout-page flow.
  The actual reset is enforced in the domain (see
  `Edenflowers.Store.LineItem.Changes.MaybeRestartCheckout`); this test
  guards against a future regression where the hook stops keeping the
  page's order assigns in sync with that reset.
  """
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias Edenflowers.Store.{LineItem, Order}

  setup %{conn: conn} do
    product = generate(product())
    variant = generate(product_variant(product_id: product.id))

    order = generate(order())

    {:ok, _line_item} =
      LineItem.add_item(%{
        order_id: order.id,
        product_variant_id: variant.id,
        quantity: 1
      })

    stale =
      order
      |> Ash.Changeset.for_update(:submit_contact_details, %{
        customer_name: "Stale Customer",
        customer_email: "stale@example.com"
      })
      |> Ash.update!(authorize?: false)

    conn = Plug.Test.init_test_session(conn, %{order_id: stale.id})

    %{conn: conn, order: stale, variant: variant}
  end

  test "removing the last line item from the cart drawer on a non-checkout page resets the order",
       %{conn: conn, order: order} do
    {:ok, view, _html} = live(conn, "/")

    [line_item] = order.line_items
    LineItem.remove_item!(line_item)

    # Force the LiveView process to drain pending messages so the hook's
    # handle_info has run before we reload the order.
    _ = render(view)

    reloaded = Order.get_for_checkout!(order.id, actor: nil)
    assert reloaded.line_items == []
    assert reloaded.state == :contact_details
    assert is_nil(reloaded.customer_name)
    assert is_nil(reloaded.customer_email)
  end

  test "removing a non-last line item on a non-checkout page leaves checkout fields intact",
       %{conn: conn, order: order, variant: variant} do
    second_variant = generate(product_variant(product_id: variant.product_id, size: :large))

    {:ok, second_line_item} =
      LineItem.add_item(%{
        order_id: order.id,
        product_variant_id: second_variant.id,
        quantity: 1
      })

    {:ok, view, _html} = live(conn, "/")

    LineItem.remove_item!(second_line_item)

    _ = render(view)

    reloaded = Order.get_for_checkout!(order.id, actor: nil)
    assert length(reloaded.line_items) == 1
    assert reloaded.customer_name == "Stale Customer"
    assert reloaded.customer_email == "stale@example.com"
  end
end
