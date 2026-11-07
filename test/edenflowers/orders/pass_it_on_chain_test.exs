defmodule Edenflowers.Orders.PassItOnChainTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Orders
  alias Edenflowers.Pricing

  setup do
    admin = generate(admin_user())
    [first_code, second_code] = Pricing.create_pass_it_on_batch!("Chain", 2, actor: admin)
    first_card = Pricing.get_pass_it_on_card!(first_code, actor: admin)
    second_card = Pricing.get_pass_it_on_card!(second_code, actor: admin)
    %{admin: admin, first_card: first_card, second_card: second_card}
  end

  test "every branch sees all live redemptions, excluding carts and cancelled uses", context do
    %{admin: admin, first_card: first_card, second_card: second_card} = context
    source = placed_order(gift: true)
    Pricing.link_card_to_gift_order!(first_card, source.id, actor: admin)
    cancelled = placed_order(promotion_id: first_card.id, fulfillment_status: :cancelled)
    generate(order(promotion_id: first_card.id))
    first = placed_order(promotion_id: first_card.id, gift: true, ordered_at: ~U[2026-10-31 10:00:00Z])
    sibling = placed_order(promotion_id: first_card.id, ordered_at: ~U[2026-11-01 10:00:00Z])
    Pricing.link_card_to_gift_order!(second_card, first.id, actor: admin)
    next = placed_order(promotion_id: second_card.id)
    expected = [source.id, first.id, next.id, sibling.id]

    for order <- [source, first, next, sibling] do
      order = Orders.get_order_for_admin!(order.id, actor: admin)
      assert Enum.map(order.pass_it_on_chain, & &1.id) == expected
    end

    # A cancelled order remains traceable on its own page, without being an active conversion elsewhere.
    cancelled = Orders.get_order_for_admin!(cancelled.id, actor: admin)
    assert Enum.any?(cancelled.pass_it_on_chain, &(&1.id == cancelled.id))
    assert Enum.any?(cancelled.pass_it_on_chain, &(&1.id == source.id))
  end

  test "cancellation cannot erase a recorded source that led to a surviving order", context do
    %{admin: admin, first_card: first_card, second_card: second_card} = context
    source = placed_order(gift: true, fulfillment_status: :cancelled)
    middle = placed_order(gift: true, promotion_id: first_card.id, fulfillment_status: :cancelled)
    next = placed_order(promotion_id: second_card.id)
    Pricing.link_card_to_gift_order!(first_card, source.id, actor: admin)
    Pricing.link_card_to_gift_order!(second_card, middle.id, actor: admin)

    for order <- [source, middle, next] do
      order = Orders.get_order_for_admin!(order.id, actor: admin)
      assert Enum.map(order.pass_it_on_chain, & &1.id) == [source.id, middle.id, next.id]
    end
  end

  test "cycles terminate and show each connected order once", context do
    %{admin: admin, first_card: first_card, second_card: second_card} = context
    first = placed_order(gift: true, promotion_id: second_card.id)
    second = placed_order(gift: true, promotion_id: first_card.id)
    Pricing.link_card_to_gift_order!(first_card, first.id, actor: admin)
    Pricing.link_card_to_gift_order!(second_card, second.id, actor: admin)

    for order <- [first, second] do
      order = Orders.get_order_for_admin!(order.id, actor: admin)
      ids = Enum.map(order.pass_it_on_chain, & &1.id)
      assert length(ids) == 2
      assert MapSet.new(ids) == MapSet.new([first.id, second.id])
    end
  end
end
