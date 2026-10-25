defmodule Edenflowers.Orders.Order.Changes.ReportUnexpectedPaymentTest do
  use Edenflowers.DataCase, async: true

  import ExUnit.CaptureLog
  import Generator

  alias Edenflowers.Orders

  defp pay_link(order, amount) do
    Orders.record_link_payment(order, "pi_link", %{amount_paid: amount},
      actor: Edenflowers.Actors.system_actor(),
      load: [:balance]
    )
  end

  test "a link payment on a cancelled order is recorded and flagged for a refund" do
    order = placed_order(payment_intent_id: "pi_link") |> Ash.Seed.update!(%{fulfillment_status: :cancelled})

    log =
      capture_log(fn ->
        assert {:ok, _order} = pay_link(order, order.grand_total)
      end)

    assert log =~ "Order #{order.id} was paid online after it was cancelled"
  end

  test "a link payment that overpays the order flags the difference" do
    order = placed_order(payment_intent_id: "pi_link", paid: "80.00")

    log =
      capture_log(fn ->
        assert {:ok, paid} = pay_link(order, "18.50")
        assert Decimal.equal?(paid.balance, "-10.00")
      end)

    assert log =~ "Order #{order.id} is overpaid by 10.00"
  end

  test "a link payment that settles the balance flags nothing" do
    order = placed_order(payment_intent_id: "pi_link", paid: "80.00")

    log = capture_log(fn -> assert {:ok, _order} = pay_link(order, "8.50") end)

    refute log =~ "Order #{order.id}"
  end
end
