defmodule EdenflowersWeb.Webhooks.StripeWebhookPlugTest do
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Mox

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders

  @secret "whsec_endpoint_integration_test"
  @path "/webhook/stripe"

  setup :set_mox_private
  setup :verify_on_exit!

  setup do
    original_secret = Application.fetch_env(:edenflowers, :stripe_webhook_secret)
    Application.put_env(:edenflowers, :stripe_webhook_secret, @secret)

    on_exit(fn ->
      case original_secret do
        {:ok, value} -> Application.put_env(:edenflowers, :stripe_webhook_secret, value)
        :error -> Application.delete_env(:edenflowers, :stripe_webhook_secret)
      end
    end)

    order = order_in_payment()
    %{order: order, payload: payment_succeeded_payload(order)}
  end

  test "a signed payment success places the order and records its Stripe payment", %{
    conn: conn,
    order: order,
    payload: payload
  } do
    conn = post_webhook(conn, payload, signature(payload))

    assert response(conn, 200) == "Webhook received."

    placed_order =
      Orders.get_order_by_id!(order.id,
        authorize?: false,
        load: [:payments, :payment_status, :amount_paid, :balance]
      )

    assert placed_order.state == :placed
    assert placed_order.payment_status == :paid
    assert placed_order.payment_intent_id == nil
    assert Decimal.equal?(placed_order.amount_paid, order.grand_total)
    assert Decimal.equal?(placed_order.balance, "0.00")

    assert [payment] = placed_order.payments
    assert payment.order_id == order.id
    assert payment.course_registration_id == nil
    assert payment.method == :stripe
    assert payment.payment_intent_id == order.payment_intent_id
    assert Decimal.equal?(payment.amount, order.grand_total)
  end

  test "a signature made with the wrong secret is rejected without placing or paying the order", %{
    conn: conn,
    order: order,
    payload: payload
  } do
    conn = post_webhook(conn, payload, signature(payload, "whsec_wrong_secret"))

    assert response(conn, 400) == "Bad request."
    assert_unpaid_checkout(order)
  end

  test "changing the raw body after signing is rejected even when the JSON is equivalent", %{
    conn: conn,
    order: order,
    payload: payload
  } do
    conn = post_webhook(conn, payload <> "\n", signature(payload))

    assert response(conn, 400) == "Bad request."
    assert_unpaid_checkout(order)
  end

  defp post_webhook(conn, payload, signature) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("stripe-signature", signature)
      |> post(@path, payload)
    end)
  end

  defp payment_succeeded_payload(order) do
    timestamp = System.system_time(:second)
    amount = StripeAPI.to_stripe_amount(order.grand_total)

    Jason.encode!(%{
      "id" => "evt_#{order.payment_intent_id}",
      "object" => "event",
      "type" => "payment_intent.succeeded",
      "created" => timestamp,
      "livemode" => false,
      "pending_webhooks" => 1,
      "request" => nil,
      "data" => %{
        "object" => %{
          "id" => order.payment_intent_id,
          "object" => "payment_intent",
          "created" => timestamp,
          "status" => "succeeded",
          "amount" => amount,
          "amount_received" => amount,
          "currency" => "eur",
          "livemode" => false,
          "payment_method" => "pm_webhook_card",
          "payment_method_types" => ["card"],
          "metadata" => %{"order_id" => order.id}
        }
      }
    })
  end

  defp signature(payload, secret \\ @secret) do
    timestamp = System.system_time(:second)

    digest =
      :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{payload}")
      |> Base.encode16(case: :lower)

    "t=#{timestamp},v1=#{digest}"
  end

  defp assert_unpaid_checkout(order) do
    unchanged_order =
      Orders.get_order_by_id!(order.id,
        authorize?: false,
        load: [:payments, :payment_status, :amount_paid]
      )

    assert unchanged_order.state == :payment
    assert unchanged_order.payment_status == :pending
    assert unchanged_order.payment_intent_id == order.payment_intent_id
    assert unchanged_order.payments == []
    assert Decimal.equal?(unchanged_order.amount_paid, "0.00")
  end
end
