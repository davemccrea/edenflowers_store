defmodule EdenflowersWeb.Webhooks.StripeHandlerRetryTest do
  # Sync because the tests add a CHECK (false) constraint, and ALTER TABLE locks
  # the table against every other test writing to it.
  use Edenflowers.DataCase

  import ExUnit.CaptureLog
  import Generator

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias EdenflowersWeb.Webhooks.StripeHandler

  setup do
    %{order: order_in_payment()}
  end

  defp payment_intent_succeeded(order) do
    %Stripe.Event{
      id: "evt_succeeded",
      type: "payment_intent.succeeded",
      data: %{
        object: %{
          id: order.payment_intent_id,
          metadata: %{"order_id" => order.id},
          amount_received: StripeAPI.to_stripe_amount(order.grand_total)
        }
      }
    }
  end

  test "payment_intent.succeeded asks Stripe to retry when the order can't be placed, and the retry places it", %{
    order: order
  } do
    # Oban recognizes this constraint name and returns {:error, changeset}.
    Edenflowers.Repo.query!("ALTER TABLE oban_jobs ADD CONSTRAINT priority_range CHECK (false) NOT VALID")

    capture_log(fn -> assert :error = StripeHandler.handle_event(payment_intent_succeeded(order)) end)
    assert %{state: :payment} = Orders.get_order_by_id!(order.id, authorize?: false)

    Edenflowers.Repo.query!("ALTER TABLE oban_jobs DROP CONSTRAINT priority_range")

    assert :ok = StripeHandler.handle_event(payment_intent_succeeded(order))

    assert %{state: :placed, payment_status: :paid} =
             Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])
  end

  test "a refund asks Stripe to retry when it can't be recorded on the order", %{order: order} do
    assert :ok = StripeHandler.handle_event(payment_intent_succeeded(order))

    Edenflowers.Repo.query!("ALTER TABLE payments ADD CONSTRAINT payments_check CHECK (false) NOT VALID")

    refund = %Stripe.Event{
      id: "evt_refund",
      type: "refund.updated",
      data: %{object: %{id: "re_1", payment_intent: order.payment_intent_id, amount: 500, status: "succeeded"}}
    }

    capture_log(fn -> assert :error = StripeHandler.handle_event(refund) end)
  end
end
