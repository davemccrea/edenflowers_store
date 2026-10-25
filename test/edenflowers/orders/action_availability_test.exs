defmodule Edenflowers.Orders.ActionAvailabilityTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Orders

  test "a fully refunded order cannot be sent a payment reminder" do
    order = generate(placed_order(refunded: true))
    order = Ash.load!(order, [:to_collect?, :payment_reminder_sendable?], authorize?: false)

    refute order.to_collect?
    refute order.payment_reminder_sendable?
    assert {:error, _} = Orders.send_payment_reminder(order, authorize?: false)
  end

  test "order email actions use the same eligibility as the admin" do
    order = generate(placed_order(fulfillment_method: :delivery))

    for {attributes, details?, confirmation?} <- [
          {%{fulfillment_status: :pending}, true, false},
          {%{fulfillment_status: :fulfilled}, true, true},
          {%{fulfillment_status: :cancelled}, false, false},
          {%{fulfillment_status: :fulfilled, fulfillment_method: :pickup}, true, false},
          {%{customer_email: nil}, false, false}
        ] do
      current = Ash.Seed.update!(order, attributes)

      loaded =
        Ash.load!(current, [:details_emailable?, :fulfillment_confirmation_sendable?],
          authorize?: false,
          reuse_values?: false
        )

      assert loaded.details_emailable? == details?
      assert loaded.fulfillment_confirmation_sendable? == confirmation?

      unless details?, do: assert({:error, _} = Orders.send_order_details_email(order, authorize?: false))

      unless confirmation?,
        do: assert({:error, _} = Orders.email_fulfillment_confirmation(order, authorize?: false))
    end
  end

  test "subscription capabilities match the permitted state transitions" do
    for {state, pause?, resume?, cancel?} <- [
          {:active, true, false, true},
          {:paused, false, true, true},
          {:payment_failed, false, false, true},
          {:cancelled, false, false, false}
        ] do
      subscription = generate(subscription(state: state))
      loaded = Ash.load!(subscription, [:pausable?, :resumable?, :cancellable?], authorize?: false)

      assert loaded.pausable? == pause?
      assert loaded.resumable? == resume?
      assert loaded.cancellable? == cancel?

      unless pause?, do: assert({:error, _} = Orders.pause_subscription(subscription, authorize?: false))
      unless resume?, do: assert({:error, _} = Orders.resume_subscription(subscription, authorize?: false))

      unless cancel?,
        do: assert({:error, _} = Orders.cancel_subscription(subscription, authorize?: false))
    end
  end
end
