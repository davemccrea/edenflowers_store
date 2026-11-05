defmodule Edenflowers.Payments.GiftVoucherTest do
  use Edenflowers.DataCase, async: true

  import ExUnit.CaptureLog
  import Generator
  import Mox
  import Swoosh.TestAssertions

  alias Edenflowers.Courses
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Workers.SendReceiptEmail
  alias Edenflowers.Payments
  alias Edenflowers.Payments.GiftVoucher
  alias Edenflowers.Payments.Workers.SendCancelledEmail

  setup :verify_on_exit!

  defp cart do
    order_in_payment(
      fulfillment_method: :pickup,
      customer_phone_number: "040 1234567",
      fulfillment_date: Date.add(Edenflowers.ShopTime.today(), 7)
    )
  end

  defp voucher(amount, opts \\ []), do: generate(gift_voucher([amount: Decimal.new(amount)] ++ opts))

  defp remaining(voucher), do: Ash.load!(voucher, :remaining, authorize?: false, reuse_values?: false).remaining

  defp money(record, fields \\ [:balance]), do: Ash.load!(record, fields, authorize?: false, reuse_values?: false)

  defp cents(amount), do: StripeAPI.to_stripe_amount(amount)

  defp succeeded(%Orders.Order{} = order, cents),
    do: %{id: order.payment_intent_id, status: "succeeded", metadata: %{"order_id" => order.id}, amount_received: cents}

  defp voucher_payments(record) do
    record
    |> Ash.load!(:payments, authorize?: false, reuse_values?: false)
    |> Map.fetch!(:payments)
    |> Enum.filter(&(&1.method == :voucher))
    |> Enum.map(&Decimal.to_string(&1.amount))
  end

  defp code_error(result) do
    assert {:error, %Ash.Error.Invalid{errors: [%{field: :code, message: message} | _]}} = result
    message
  end

  describe "codes" do
    test "are 12 characters that can't be misread, and are found however they're typed" do
      code = GiftVoucher.generate_code()
      assert code =~ ~r/\A[0-9A-HJKMNP-TV-Z]{12}\z/

      assert GiftVoucher.format_code("A0B1C2D3E4F5") == "A0B1-C2D3-E4F5"
      assert GiftVoucher.normalize_code(" aOb-ic2d 3e4f5") == "A0B1C2D3E4F5"
      assert GiftVoucher.normalize_code("a0blc2d3e4f5") == "A0B1C2D3E4F5"
    end
  end

  describe "paying at store checkout" do
    test "the voucher pays part when the order is placed, and Stripe the rest" do
      order = cart()
      voucher = voucher("10.00")
      typed = voucher.code |> GiftVoucher.format_code() |> String.downcase()

      order = Orders.add_gift_voucher_with_code!(order, typed, actor: nil)
      assert Decimal.eq?(remaining(voucher), "10.00"), "nothing is spent until the order is placed"

      %{payment_intent_id: pi} = order
      card_cents = cents(Decimal.sub(order.grand_total, 10))
      expect(StripeAPI.Mock, :update_payment_intent, fn ^pi, ^card_cents -> {:ok, %{}} end)

      expect(StripeAPI.Mock, :retrieve_payment_intent, fn _ ->
        {:ok, %{id: pi, client_secret: "pi_secret", customer: nil}}
      end)

      assert {:ok, %{client_secret: "pi_secret"}} = Orders.prepare_checkout_payment(order.id, actor: nil)
      assert {:ok, :completed} = Payments.complete(succeeded(order, card_cents))

      placed = Orders.get_order_by_id!(order.id, authorize?: false)
      assert placed.state == :placed
      assert Decimal.eq?(money(placed).balance, 0)
      assert voucher_payments(placed) == ["10.00"]
      assert Decimal.eq?(remaining(voucher), 0)
    end

    test "a voucher that covers the order places it without charging a card" do
      order = cart()
      voucher = voucher("500.00")
      order = Orders.add_gift_voucher_with_code!(order, voucher.code, actor: nil)

      # The PaymentIntent opened before the voucher went on.
      %{payment_intent_id: pi} = order
      expect(StripeAPI.Mock, :cancel_payment_intent, fn %{id: ^pi} -> {:ok, %{id: pi, status: "canceled"}} end)

      assert {:ok, %{client_secret: nil, payable: %{state: :placed}}} =
               Orders.prepare_checkout_payment(order.id, actor: nil)

      assert Decimal.eq?(remaining(voucher), Decimal.sub(500, order.grand_total))
      assert [_job] = all_enqueued(worker: SendReceiptEmail, args: %{"primary_key" => %{"id" => order.id}})
    end

    test "a voucher that nearly covers the order leaves Stripe its 0.50 € minimum" do
      order = cart()
      voucher = voucher(Decimal.sub(order.grand_total, "0.20") |> Decimal.to_string())

      order =
        order
        |> Orders.add_gift_voucher_with_code!(voucher.code, actor: nil)
        |> money([:voucher_amount, :stripe_amount])

      assert Decimal.eq?(order.stripe_amount, "0.50")
      assert Decimal.eq?(order.voucher_amount, Decimal.sub(order.grand_total, "0.50"))
    end

    test "a voucher spent elsewhere meanwhile still places the order, leaving the gap to collect" do
      order = cart()
      voucher = voucher("10.00")
      order = Orders.add_gift_voucher_with_code!(order, voucher.code, actor: nil)
      card_cents = cents(Decimal.sub(order.grand_total, 10))

      other = placed_order()
      generate(payment(order_id: other.id, method: :voucher, gift_voucher_id: voucher.id, amount: Decimal.new(10)))

      log = capture_log(fn -> assert {:ok, :completed} = Payments.complete(succeeded(order, card_cents)) end)
      assert log =~ "Amount mismatch"

      placed = Orders.get_order_by_id!(order.id, authorize?: false)
      assert placed.state == :placed
      assert Decimal.eq?(money(placed).balance, 10)
      assert voucher_payments(placed) == []
    end

    test "refuses unknown, expired and used-up vouchers, saying why" do
      order = cart()

      assert code_error(Orders.add_gift_voucher_with_code(order, "NOPE-NOPE", actor: nil)) =~ "couldn't find"

      expired = voucher("50.00", expires_on: Date.add(Edenflowers.ShopTime.today(), -1))
      assert code_error(Orders.add_gift_voucher_with_code(order, expired.code, actor: nil)) =~ "expired on"

      used_up = voucher("10.00")

      generate(
        payment(order_id: placed_order().id, method: :voucher, gift_voucher_id: used_up.id, amount: Decimal.new(10))
      )

      assert code_error(Orders.add_gift_voucher_with_code(order, used_up.code, actor: nil)) =~ "used up"
    end

    test "rate-limits codes tried on a cart, even the right one" do
      order = cart()
      voucher = voucher("10.00")

      for _attempt <- 1..10, do: Orders.add_gift_voucher_with_code(order, "WRONG", actor: nil)

      assert {:error, %Ash.Error.Forbidden{errors: [%AshRateLimiter.LimitExceeded{} | _]}} =
               Orders.add_gift_voucher_with_code(order, voucher.code, actor: nil)
    end
  end

  describe "paying at course checkout" do
    test "a voucher that covers the booking confirms it without Stripe" do
      registration = generate(course_registration(amount: Decimal.new("85.00")))
      voucher = voucher("100.00")

      registration = Courses.add_registration_gift_voucher!(registration, voucher.code, actor: nil)

      assert {:ok, %{client_secret: nil, payable: %{status: :confirmed}}} =
               Courses.prepare_registration_checkout_payment(registration.id, registration.course_id, actor: nil)

      assert voucher_payments(registration) == ["85.00"]
      assert Decimal.eq?(remaining(voucher), 15)
    end

    test "asks Stripe only for what the voucher doesn't cover" do
      registration = generate(course_registration(amount: Decimal.new("85.00")))
      voucher = voucher("30.00")
      registration = Courses.add_registration_gift_voucher!(registration, voucher.code, actor: nil)
      id = registration.id

      expect(StripeAPI.Mock, :create_payment_intent, fn 5500, %{"course_registration_id" => ^id}, nil ->
        {:ok, %{id: "pi_course_voucher", client_secret: "pi_secret", amount: 5500}}
      end)

      assert {:ok, %{client_secret: "pi_secret"}} =
               Courses.prepare_registration_checkout_payment(id, registration.course_id, actor: nil)

      intent = %{
        id: "pi_course_voucher",
        status: "succeeded",
        metadata: %{"course_registration_id" => id},
        amount_received: 5500
      }

      assert {:ok, :completed} = Payments.complete(intent)
      assert voucher_payments(registration) == ["30.00"]
      assert Decimal.eq?(money(registration).balance, 0)
    end
  end

  describe "handing back" do
    setup do
      %{admin: generate(admin_user())}
    end

    defp order_paid(payments) do
      voucher = voucher("100.00")
      order = placed_order(payment_intent_id: nil, gift_voucher_id: voucher.id)

      for {method, amount} <- payments do
        voucher_id = if method == :voucher, do: voucher.id
        pi = if method == :stripe, do: "pi_#{order.id}"

        generate(
          payment(
            order_id: order.id,
            method: method,
            amount: Decimal.new(amount),
            gift_voucher_id: voucher_id,
            payment_intent_id: pi
          )
        )
      end

      %{order: order, voucher: voucher}
    end

    test "cancelling puts what the voucher paid back onto it, and says so", %{admin: admin} do
      %{order: order, voucher: voucher} = order_paid(voucher: "88.50")
      assert Decimal.eq?(remaining(voucher), "11.50")

      assert {:ok, cancelled} = Orders.cancel_order(order, %{}, actor: admin)

      assert Decimal.eq?(remaining(voucher), 100)
      assert Decimal.eq?(money(cancelled).balance, 0)

      [job] = all_enqueued(worker: SendCancelledEmail)
      assert :ok = perform_job(SendCancelledEmail, job.args)
      assert_email_sent(fn email -> assert email.text_body =~ "back on your gift voucher" end)
    end

    test "cancelling with a charge refunds the card first, then the voucher", %{admin: admin} do
      %{order: order, voucher: voucher} = order_paid(stripe: "50.00", voucher: "38.50")
      pi = "pi_#{order.id}"

      StripeAPI.Mock
      |> stub(:list_refunds, fn ^pi -> {:ok, []} end)
      |> expect(:create_refund, fn ^pi, 5000, _key, _metadata ->
        {:ok, %{id: "re_#{order.id}", payment_intent: pi, amount: 5000, status: "succeeded"}}
      end)

      assert {:ok, _cancelled} = Orders.cancel_order(order, %{cancellation_charge: "20.00"}, actor: admin)

      # 68.50 owed back: 50.00 to the card, 18.50 onto the voucher, which keeps 20.00 spent.
      assert Decimal.eq?(remaining(voucher), 80)
    end

    test "Jennie hands money back onto the voucher, never as cash" do
      %{order: order, voucher: voucher} = order_paid(voucher: "88.50")

      refund = fn method ->
        order
        |> Ash.Changeset.for_update(:refund, %{amount: "10.00", payment_method: method, email_customer?: false},
          authorize?: false
        )
        |> Ash.update()
      end

      assert {:error, _not_paid_in_cash} = refund.(:cash)
      assert {:ok, _order} = refund.(:voucher)
      assert Decimal.eq?(remaining(voucher), "21.50")
    end
  end
end
