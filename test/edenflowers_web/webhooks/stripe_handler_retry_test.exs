defmodule EdenflowersWeb.Webhooks.StripeHandlerRetryTest do
  # Sync because the tests add a CHECK (false) constraint, and ALTER TABLE locks
  # the table against every other test writing to it.
  use Edenflowers.DataCase

  import ExUnit.CaptureLog
  import Generator

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias EdenflowersWeb.Webhooks.StripeHandler

  setup do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    product_variant = generate(product_variant(product_id: product.id))
    fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate.id))
    %{fulfillment_fee: fulfillment_fee} = Edenflowers.Fulfillment.Fee.calculate(fulfillment_option, 0)

    {:ok, user} = Edenflowers.Accounts.upsert_user("john.smith@example.com", "John Smith", authorize?: false)

    seeded =
      Ash.Seed.seed!(Order, %{
        order_reference: :crypto.strong_rand_bytes(6) |> Base.encode16(),
        state: :payment,
        customer_name: "John Smith",
        customer_email: "john.smith@example.com",
        user_id: user.id,
        fulfillment_option_id: fulfillment_option.id,
        fulfillment_date: Date.utc_today(),
        quoted_fulfillment_fee: fulfillment_fee,
        payment_intent_id: "pi_order_#{System.unique_integer([:positive])}"
      })

    generate(line_item(order_id: seeded.id, product_variant_id: product_variant.id, quantity: 1))

    %{order: Ash.get!(Order, seeded.id, load: [:grand_total], authorize?: false)}
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
