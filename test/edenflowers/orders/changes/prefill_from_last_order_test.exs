defmodule Edenflowers.Orders.Changes.PrefillFromLastOrderTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Orders

  setup do
    user = generate(admin_user(admin: false))
    delivery = generate(fulfillment_option(fulfillment_method: :delivery))
    pickup = generate(fulfillment_option(fulfillment_method: :pickup))

    %{user: user, delivery: delivery, pickup: pickup}
  end

  defp last_order(user, attrs) do
    generate(
      order(
        Keyword.merge(
          [
            state: :placed,
            user_id: user.id,
            ordered_at: DateTime.utc_now(),
            fulfillment_method: :delivery,
            recipient_phone_number: "+358401111111",
            delivery_address: "Kauppatori 1, Helsinki",
            delivery_instructions: "Door code 1234",
            geocoded_address: "Kauppatori 1, 00170 Helsinki",
            distance: 1200
          ],
          attrs
        )
      )
    )
  end

  defp choose(order, option, actor) do
    Orders.update_fulfillment_option!(order, option.id, actor: actor, authorize?: false)
  end

  test "fills phone and address from the customer's last own delivery", %{user: user, delivery: delivery} do
    last_order(user, [])
    order = generate(order(state: :delivery, user_id: user.id))

    order = choose(order, delivery, user)

    assert order.recipient_phone_number == "+358401111111"
    assert order.delivery_address == "Kauppatori 1, Helsinki"
    assert order.delivery_instructions == "Door code 1234"
    assert order.distance == 1200
  end

  test "fills on entering the delivery step when the option was already chosen", %{user: user, delivery: delivery} do
    last_order(user, [])

    order =
      generate(
        order(state: :gift_options, user_id: user.id, fulfillment_option_id: delivery.id, fulfillment_method: :delivery)
      )

    order = Orders.submit_gift_options!(order, %{gift: false}, actor: user, authorize?: false)

    assert order.delivery_address == "Kauppatori 1, Helsinki"
    assert order.delivery_instructions == "Door code 1234"
  end

  test "keeps an address already on the order", %{user: user} do
    last_order(user, [])

    order =
      generate(
        order(
          state: :gift_options,
          user_id: user.id,
          fulfillment_method: :delivery,
          delivery_address: "Typed street 3",
          recipient_phone_number: "+358403333333"
        )
      )

    order = Orders.submit_gift_options!(order, %{gift: false}, actor: user, authorize?: false)

    assert order.delivery_address == "Typed street 3"
    assert order.recipient_phone_number == "+358403333333"
  end

  test "fills only the phone for pickup", %{user: user, pickup: pickup} do
    last_order(user, [])
    order = generate(order(state: :delivery, user_id: user.id))

    order = choose(order, pickup, user)

    assert order.recipient_phone_number == "+358401111111"
    assert is_nil(order.delivery_address)
  end

  test "skips a last order that was a gift delivery", %{user: user, delivery: delivery} do
    last_order(user, recipient_phone_number: "+358402222222", ordered_at: DateTime.add(DateTime.utc_now(), -1, :day))
    last_order(user, gift: true, recipient_phone_number: "+358409999999", delivery_address: "Recipient's street 5")
    order = generate(order(state: :delivery, user_id: user.id))

    order = choose(order, delivery, user)

    assert order.recipient_phone_number == "+358402222222"
    assert order.delivery_address == "Kauppatori 1, Helsinki"
  end

  test "leaves a gift delivery empty", %{user: user, delivery: delivery} do
    last_order(user, [])
    order = generate(order(state: :delivery, user_id: user.id, gift: true))

    order = choose(order, delivery, user)

    assert is_nil(order.recipient_phone_number)
    assert is_nil(order.delivery_address)
  end

  test "never fills for a guest assigned to an account by email", %{user: user, delivery: delivery} do
    last_order(user, [])
    order = generate(order(state: :delivery, user_id: user.id))

    order = choose(order, delivery, nil)

    assert is_nil(order.recipient_phone_number)
    assert is_nil(order.delivery_address)
  end
end
