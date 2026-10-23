defmodule Edenflowers.Orders.CancelByCustomerTest do
  use Edenflowers.DataCase, async: true

  import ExUnit.CaptureLog
  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Payments.Workers.SendCancelledEmail
  alias Edenflowers.ShopTime

  setup do
    %{customer: generate(admin_user(admin: false))}
  end

  defp days_ahead(days), do: Date.add(ShopTime.today(), days)

  defp paid_order(customer, opts \\ []) do
    order =
      placed_order(
        Keyword.merge(
          [user_id: customer.id, payment_intent_id: nil, fulfillment_date: days_ahead(5)],
          opts
        )
      )

    generate(payment(order_id: order.id, amount: order.grand_total, payment_intent_id: "pi_#{order.id}"))
    order
  end

  defp expect_refund(order) do
    pi = "pi_#{order.id}"

    StripeAPI.Mock
    |> Mox.stub(:list_refunds, fn ^pi -> {:ok, []} end)
    |> Mox.expect(:create_refund, fn ^pi, cents, _key, _metadata ->
      {:ok, %{id: "re_#{order.id}", payment_intent: pi, amount: cents, status: "succeeded"}}
    end)
  end

  test "cancels, refunds in full, confirms it to the customer and sends Jennie a shop notice", %{customer: customer} do
    order = paid_order(customer)
    expect_refund(order)

    assert {:ok, cancelled} = Orders.cancel_order_by_customer(order, actor: customer)

    cancelled = Ash.load!(cancelled, [:amount_paid, :payment_status], authorize?: false)
    assert cancelled.fulfillment_status == :cancelled
    assert Decimal.equal?(cancelled.amount_paid, 0)
    assert cancelled.payment_status == :refunded

    [job] = all_enqueued(worker: SendCancelledEmail)
    assert :ok = perform_job(SendCancelledEmail, job.args)

    assert_email_sent(fn email ->
      assert email.subject == "Order #{order.order_reference} cancelled"
      assert {"Eden Flowers", _address} = email.from
      # Only a record copy: Jennie hears about it from the shop notice.
      assert email.bcc == [{"Jennie", "info+copy@edenflowers.fi"}]
      assert email.text_body =~ "Refund: €88.50"
      assert email.text_body =~ "Refunds usually take 3–5 working days to appear on your statement."
    end)

    assert_enqueued(
      worker: Edenflowers.Orders.Workers.EmailShop,
      args: %{"notice" => "cancelled", "order_id" => order.id}
    )
  end

  test "is closed 4 days or fewer before the fulfillment date", %{customer: customer} do
    order = paid_order(customer, fulfillment_date: days_ahead(4))

    assert {:error, %Ash.Error.Invalid{}} = Orders.cancel_order_by_customer(order, actor: customer)
    assert Orders.get_order_by_id!(order.id, authorize?: false).fulfillment_status == :pending
  end

  test "refuses Custom Orders and orders paid in person", %{customer: customer} do
    custom = paid_order(customer, origin: :custom)
    in_person = paid_order(customer)
    generate(payment(order_id: in_person.id, amount: Decimal.new("5.00"), method: :cash))

    assert {:error, _} = Orders.cancel_order_by_customer(custom, actor: customer)
    assert {:error, _} = Orders.cancel_order_by_customer(in_person, actor: customer)
  end

  test "refuses another customer's order", %{customer: customer} do
    order = paid_order(generate(admin_user(admin: false)))

    assert {:error, %Ash.Error.Forbidden{}} = Orders.cancel_order_by_customer(order, actor: customer)
  end

  test "a refund Stripe refuses leaves the order placed", %{customer: customer} do
    order = paid_order(customer)

    StripeAPI.Mock
    |> Mox.stub(:list_refunds, fn _pi -> {:ok, []} end)
    |> Mox.expect(:create_refund, fn _pi, _cents, _key, _metadata -> {:error, :charge_disputed} end)

    log =
      capture_log(fn ->
        assert {:error, %Ash.Error.Invalid{}} = Orders.cancel_order_by_customer(order, actor: customer)
      end)

    assert log =~ "Could not refund"
    assert Orders.get_order_by_id!(order.id, authorize?: false).fulfillment_status == :pending
    refute_enqueued(worker: SendCancelledEmail)
  end

  test "a cancelled order gives its promotion code back", %{customer: customer} do
    promotion = generate(promotion(usage_limit: 1))
    order = paid_order(customer, promotion_id: promotion.id)
    expect_refund(order)

    assert Ash.load!(promotion, :usage, authorize?: false).usage == 1
    {:ok, _} = Orders.cancel_order_by_customer(order, actor: customer)
    assert Ash.load!(promotion, :usage, authorize?: false, reuse_values?: false).usage == 0
  end
end
