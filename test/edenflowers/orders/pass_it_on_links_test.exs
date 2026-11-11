defmodule Edenflowers.Orders.PassItOnLinksTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Orders
  alias Edenflowers.Pricing

  test "direct redemptions exclude cancellations and carts and sort by date then id" do
    admin = generate(admin_user())
    [code] = Pricing.create_pass_it_on_batch!("Links", 1, actor: admin)
    card = Pricing.get_pass_it_on_card!(code, actor: admin)
    source = placed_order(gift: true)
    Pricing.link_card_to_gift_order!(card, source.id, actor: admin)
    generate(order(promotion_id: card.id))
    later = placed_order(promotion_id: card.id, ordered_at: ~U[2026-11-01 10:00:00Z])
    first = placed_order(promotion_id: card.id, ordered_at: ~U[2026-10-31 10:00:00Z])

    placed_order(promotion_id: card.id, fulfillment_status: :cancelled, ordered_at: ~U[2026-10-31 10:00:00Z])

    source = Orders.get_order_for_admin!(source.id, actor: admin)
    assert Enum.map(source.pass_it_on_card.placed_orders, & &1.id) == [first.id, later.id]
  end

  test "a cancelled gift stays the source but is not a redemption, including historical cycles" do
    admin = generate(admin_user())
    [first_code, second_code] = Pricing.create_pass_it_on_batch!("Links", 2, actor: admin)
    first_card = Pricing.get_pass_it_on_card!(first_code, actor: admin)
    second_card = Pricing.get_pass_it_on_card!(second_code, actor: admin)
    first = placed_order(gift: true, promotion_id: second_card.id, fulfillment_status: :cancelled)
    second = placed_order(gift: true, promotion_id: first_card.id)
    Pricing.link_card_to_gift_order!(first_card, first.id, actor: admin)
    Pricing.link_card_to_gift_order!(second_card, second.id, actor: admin)

    for {order, source, redemptions} <- [{first, second, [second.id]}, {second, first, []}] do
      order = Orders.get_order_for_admin!(order.id, actor: admin)
      assert order.promotion.gift_order.id == source.id
      assert order.promotion.gift_order.committed?
      assert Enum.map(order.pass_it_on_card.placed_orders, & &1.id) == redemptions
    end
  end
end
