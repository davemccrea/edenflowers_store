defmodule EdenflowersWeb.StripeHandlerTest do
  use Edenflowers.DataCase

  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Store.Order

  describe "StripeHandler" do
    test "updates order and sends a confirmation email" do
      order = generate(order())

      order =
        order
        |> Ash.Changeset.for_update(:save_step_1, %{
          customer_name: "John Smith",
          customer_email: "john.smith@example.com"
        })
        |> Ash.update!()

      assert :ok =
               EdenflowersWeb.StripeHandler.handle_event(%Stripe.Event{
                 type: "payment_intent.succeeded",
                 data: %{object: %{metadata: %{"order_id" => order.id}}}
               })

      order = Order.get_by_id!(order.id)
      assert order.state == :order
      assert order.payment_status == :paid

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)

      assert_email_sent()
    end
  end
end
