defmodule EdenflowersWeb.Webhooks.StripeHandlerTest do
  use Edenflowers.DataCase, async: true

  import ExUnit.CaptureLog
  import Generator
  import Mox
  import Swoosh.TestAssertions

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias EdenflowersWeb.Webhooks.StripeHandler

  setup :verify_on_exit!

  setup do
    order = order_in_payment()

    # Derive the expected Stripe amount from the order's real grand_total via the
    # same conversion the handler uses, so the fixture can't silently diverge from
    # production's rounding.
    expected_amount = StripeAPI.to_stripe_amount(order.grand_total)

    %{order: order, expected_amount: expected_amount}
  end

  describe "setup_intent.succeeded" do
    test "stores the new card and returns a held subscription to active", %{order: order} do
      subscription = generate(subscription(user_id: order.user_id, state: :payment_failed))

      assert :ok = StripeHandler.handle_event(setup_intent_succeeded(subscription))

      assert %{state: :active, stripe_payment_method_id: "pm_new"} = Ash.reload!(subscription, authorize?: false)
    end

    @tag capture_log: true
    test "acknowledges a card saved to a cancelled subscription, so Stripe stops retrying", %{order: order} do
      subscription = generate(subscription(user_id: order.user_id, state: :cancelled))

      assert :ok = StripeHandler.handle_event(setup_intent_succeeded(subscription))

      assert %{state: :cancelled, stripe_payment_method_id: "pm_card"} = Ash.reload!(subscription, authorize?: false)
    end

    @tag capture_log: true
    test "asks Stripe to retry when the card can't be saved for another reason" do
      missing_subscription = %{id: Ecto.UUID.generate()}

      assert :error = StripeHandler.handle_event(setup_intent_succeeded(missing_subscription))
    end

    defp setup_intent_succeeded(subscription) do
      %Stripe.Event{
        id: "evt_setup_1",
        type: "setup_intent.succeeded",
        data: %{
          object: %{
            id: "seti_1",
            status: "succeeded",
            payment_method: "pm_new",
            metadata: %{"subscription_id" => subscription.id}
          }
        }
      }
    end
  end

  describe "payment_intent.succeeded" do
    test "finalizes the order, marks it paid, and enqueues a confirmation email", %{
      order: order,
      expected_amount: expected_amount
    } do
      assert :ok =
               StripeHandler.handle_event(%Stripe.Event{
                 id: "evt_succeeded_1",
                 type: "payment_intent.succeeded",
                 data: %{
                   object: %{
                     id: order.payment_intent_id,
                     metadata: %{"order_id" => order.id},
                     amount_received: expected_amount
                   }
                 }
               })

      order = Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])
      assert order.state == :placed
      assert order.payment_status == :paid
      assert order.payment_intent_id == nil

      assert %{success: 2, failure: 0} = Oban.drain_queue(queue: :default)

      assert_email_sent()
    end

    test "is idempotent on redelivery for an already-placed order", %{
      order: order,
      expected_amount: expected_amount
    } do
      event = %Stripe.Event{
        id: "evt_succeeded_dup",
        type: "payment_intent.succeeded",
        data: %{
          object: %{
            id: order.payment_intent_id,
            metadata: %{"order_id" => order.id},
            amount_received: expected_amount
          }
        }
      }

      # First delivery — finalizes + enqueues.
      assert :ok = StripeHandler.handle_event(event)
      # Stripe redelivers the same event after we've already processed it. The
      # handler must still return :ok so Stripe stops retrying, and the order,
      # already placed, queues no second receipt.
      assert :ok = StripeHandler.handle_event(event)

      order = Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])
      assert order.state == :placed
      assert order.payment_status == :paid

      assert %{success: 2, failure: 0} = Oban.drain_queue(queue: :default)
    end

    test "places the order and flags the mismatch when amount_received does not match grand_total", %{
      order: order,
      expected_amount: expected_amount
    } do
      log =
        capture_log(fn ->
          assert :ok =
                   StripeHandler.handle_event(%Stripe.Event{
                     id: "evt_amount_mismatch",
                     type: "payment_intent.succeeded",
                     data: %{
                       object: %{
                         id: order.payment_intent_id,
                         metadata: %{"order_id" => order.id},
                         amount_received: expected_amount - 1
                       }
                     }
                   })
        end)

      assert log =~ "Amount mismatch"

      order =
        Orders.get_order_by_id!(order.id, authorize?: false, load: [:balance, :amount_paid, :payment_status])

      assert order.state == :placed
      assert order.payment_status == :pending
      assert Decimal.equal?(order.amount_paid, Decimal.div(expected_amount - 1, 100))
      assert Decimal.equal?(order.balance, Decimal.new("0.01"))
    end

    test "logs error and returns :ok when payment_intent_id does not match", %{
      order: order,
      expected_amount: expected_amount
    } do
      log =
        capture_log(fn ->
          assert :ok =
                   StripeHandler.handle_event(%Stripe.Event{
                     id: "evt_pi_mismatch",
                     type: "payment_intent.succeeded",
                     data: %{
                       object: %{
                         id: "pi_wrong_#{:rand.uniform(1_000_000)}",
                         metadata: %{"order_id" => order.id},
                         amount_received: expected_amount
                       }
                     }
                   })
        end)

      assert log =~ "payment_intent mismatch"

      order = Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])
      assert order.state == :payment
      assert order.payment_status != :paid
      refute_email_sent()
    end

    test "returns :ok when metadata.order_id is missing (permanent failure, stop retries)", %{order: order} do
      capture_log(fn ->
        assert :ok =
                 StripeHandler.handle_event(%Stripe.Event{
                   id: "evt_no_metadata",
                   type: "payment_intent.succeeded",
                   data: %{object: %{id: order.payment_intent_id, metadata: %{}}}
                 })
      end)

      assert %{success: 0, failure: 0} = Oban.drain_queue(queue: :default)
      refute_email_sent()
    end
  end

  describe "payment_intent.payment_failed" do
    test "leaves the order and the course booking for the customer to retry", %{order: order} do
      registration =
        generate(course_registration(amount: Decimal.new("170.00"), payment_intent_id: "pi_course_failed"))

      for metadata <- [%{"order_id" => order.id}, %{"course_registration_id" => registration.id}] do
        assert :ok =
                 StripeHandler.handle_event(%Stripe.Event{
                   id: "evt_failed",
                   type: "payment_intent.payment_failed",
                   data: %{object: %{id: "pi_failed", metadata: metadata}}
                 })
      end

      order = Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])
      assert order.state == :payment
      assert order.payment_status == :pending
      assert Edenflowers.Courses.get_registration_by_id!(registration.id, authorize?: false).status == :pending

      refute_email_sent()
    end
  end

  describe "payment_intent.canceled" do
    test "clears the canceled intent so the order can open a fresh one", %{order: order} do
      assert :ok =
               StripeHandler.handle_event(%Stripe.Event{
                 id: "evt_canceled_1",
                 type: "payment_intent.canceled",
                 data: %{object: %{id: order.payment_intent_id, metadata: %{"order_id" => order.id}}}
               })

      order = Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])
      assert order.state == :payment
      assert order.payment_status == :pending
      assert order.payment_intent_id == nil
    end
  end

  describe "unhandled events" do
    test "returns :ok for an unhandled event type" do
      capture_log(fn ->
        assert :ok =
                 StripeHandler.handle_event(%Stripe.Event{
                   id: "evt_random",
                   type: "invoice.paid",
                   data: %{object: %{}}
                 })
      end)
    end
  end

  describe "a custom order's payment link" do
    setup %{order: order} do
      %{order: Ash.Seed.update!(order, %{state: :placed, origin: :custom, order_reference: "LINK1"})}
    end

    defp link_succeeded(order, amount_received) do
      StripeHandler.handle_event(%Stripe.Event{
        id: "evt_link_succeeded",
        type: "payment_intent.succeeded",
        data: %{
          object: %{id: order.payment_intent_id, metadata: %{"order_id" => order.id}, amount_received: amount_received}
        }
      })
    end

    test "records the payment on the order already placed", %{order: order, expected_amount: expected_amount} do
      assert :ok = link_succeeded(order, expected_amount)

      order = Orders.get_order_by_id!(order.id, authorize?: false, load: [:payments, :payment_status])
      assert order.payment_status == :paid
      assert [%{method: :stripe, payment_intent_id: payment_intent_id}] = order.payments
      assert payment_intent_id != nil
      assert order.payment_intent_id == nil
      assert order.order_reference == "LINK1"
    end

    test "records a redelivered payment only once", %{order: order, expected_amount: expected_amount} do
      assert :ok = link_succeeded(order, expected_amount)
      assert :ok = link_succeeded(order, expected_amount)

      assert [_payment] = Orders.get_order_by_id!(order.id, authorize?: false, load: [:payments]).payments
    end

    test "records a payment for an order already paid in person, and alerts Jennie to refund it", %{
      order: order,
      expected_amount: expected_amount
    } do
      generate(payment(order_id: order.id, method: :zettle, amount: Decimal.div(expected_amount, 100)))

      log = capture_log(fn -> assert :ok = link_succeeded(order, expected_amount) end)

      assert log =~ "overpaid"
      assert log =~ "Refund the difference in Stripe"
      order = Orders.get_order_by_id!(order.id, authorize?: false, load: [:balance])
      assert Decimal.equal?(order.balance, Decimal.negate(Decimal.div(expected_amount, 100)))
    end
  end

  describe "a refund delivered before its payment" do
    test "asks Stripe to retry, then records the refund once after the payment arrives", %{
      order: order,
      expected_amount: expected_amount
    } do
      payment_intent = %{
        id: order.payment_intent_id,
        metadata: %{"order_id" => order.id},
        amount_received: expected_amount
      }

      expect(StripeAPI.Mock, :retrieve_payment_intent, fn %{payment_intent_id: id} ->
        assert id == order.payment_intent_id
        {:ok, payment_intent}
      end)

      refund = %Stripe.Event{
        id: "evt_refund_early",
        type: "refund.created",
        data: %{object: %{id: "re_early", payment_intent: order.payment_intent_id, amount: 500, status: "succeeded"}}
      }

      capture_log(fn -> assert :error = StripeHandler.handle_event(refund) end)

      assert :ok =
               StripeHandler.handle_event(%Stripe.Event{
                 id: "evt_paid_later",
                 type: "payment_intent.succeeded",
                 data: %{object: payment_intent}
               })

      assert :ok = StripeHandler.handle_event(refund)
      assert :ok = StripeHandler.handle_event(refund)

      payments = Orders.get_order_by_id!(order.id, authorize?: false, load: [:payments]).payments
      assert [refund] = Enum.filter(payments, &(&1.stripe_refund_id == "re_early"))
      assert Decimal.equal?(refund.amount, "-5.00")
    end
  end

  describe "looking up a refund's missing payment" do
    test "asks Stripe to retry when the payment lookup fails" do
      expect(StripeAPI.Mock, :retrieve_payment_intent, fn %{payment_intent_id: "pi_lookup"} ->
        {:error, :unavailable}
      end)

      event = %Stripe.Event{
        id: "evt_refund_lookup",
        type: "refund.updated",
        data: %{object: %{id: "re_lookup", payment_intent: "pi_lookup", amount: 500, status: "succeeded"}}
      }

      capture_log(fn -> assert :error = StripeHandler.handle_event(event) end)
    end

    test "also retries an early course refund, then records it after confirmation" do
      registration =
        generate(course_registration(course_id: generate(course()).id, payment_intent_id: "pi_early_course"))

      payment_intent = %{
        id: registration.payment_intent_id,
        metadata: %{"course_registration_id" => registration.id},
        amount_received: StripeAPI.to_stripe_amount(registration.amount)
      }

      expect(StripeAPI.Mock, :retrieve_payment_intent, fn %{payment_intent_id: "pi_early_course"} ->
        {:ok, payment_intent}
      end)

      refund = %Stripe.Event{
        id: "evt_course_refund_early",
        type: "refund.updated",
        data: %{
          object: %{
            id: "re_early_course",
            payment_intent: registration.payment_intent_id,
            amount: 500,
            status: "succeeded"
          }
        }
      }

      capture_log(fn -> assert :error = StripeHandler.handle_event(refund) end)

      assert :ok =
               StripeHandler.handle_event(%Stripe.Event{
                 id: "evt_course_paid_later",
                 type: "payment_intent.succeeded",
                 data: %{object: payment_intent}
               })

      assert :ok = StripeHandler.handle_event(refund)
      assert :ok = StripeHandler.handle_event(refund)

      registration = Edenflowers.Courses.get_registration_by_id!(registration.id, authorize?: false, load: [:payments])
      assert [refund] = Enum.filter(registration.payments, &(&1.stripe_refund_id == "re_early_course"))
      assert Decimal.equal?(refund.amount, "-5.00")
    end
  end

  describe "a refund made in the Stripe dashboard" do
    setup %{order: order, expected_amount: expected_amount} do
      payment_intent_id = order.payment_intent_id

      assert :ok =
               StripeHandler.handle_event(%Stripe.Event{
                 id: "evt_paid",
                 type: "payment_intent.succeeded",
                 data: %{
                   object: %{
                     id: payment_intent_id,
                     metadata: %{"order_id" => order.id},
                     amount_received: expected_amount
                   }
                 }
               })

      %{payment_intent_id: payment_intent_id}
    end

    defp refund_event(type, payment_intent_id, status) do
      %Stripe.Event{
        id: "evt_refund",
        type: type,
        data: %{object: %{id: "re_1", payment_intent: payment_intent_id, amount: 500, status: status}}
      }
    end

    defp refunds(order) do
      Orders.get_order_by_id!(order.id, authorize?: false, load: [:payments]).payments
      |> Enum.filter(&Decimal.negative?(&1.amount))
    end

    test "is recorded against the order once it succeeds, only once", %{order: order, payment_intent_id: pi} do
      assert :ok = StripeHandler.handle_event(refund_event("refund.created", pi, "pending"))
      assert [] = refunds(order)

      assert :ok = StripeHandler.handle_event(refund_event("refund.updated", pi, "succeeded"))
      assert :ok = StripeHandler.handle_event(refund_event("refund.updated", pi, "succeeded"))

      assert [refund] = refunds(order)
      assert Decimal.equal?(refund.amount, "-5.00")
      assert refund.stripe_refund_id == "re_1"
    end

    test "is never recorded when a pending refund fails", %{order: order, payment_intent_id: pi} do
      balance_before = Orders.get_order_by_id!(order.id, authorize?: false, load: [:balance]).balance

      assert :ok = StripeHandler.handle_event(refund_event("refund.created", pi, "pending"))
      assert :ok = StripeHandler.handle_event(refund_event("refund.updated", pi, "failed"))

      assert [] = refunds(order)
      balance_after = Orders.get_order_by_id!(order.id, authorize?: false, load: [:balance]).balance
      assert Decimal.equal?(balance_after, balance_before)
    end

    test "of a payment the shop doesn't know is ignored" do
      expect(StripeAPI.Mock, :retrieve_payment_intent, fn %{payment_intent_id: "pi_course"} ->
        {:ok, %{id: "pi_course", metadata: %{}}}
      end)

      assert :ok =
               StripeHandler.handle_event(refund_event("refund.created", "pi_course", "succeeded"))

      refute Enum.any?(Ash.read!(Edenflowers.Payments.Payment, authorize?: false), &(&1.stripe_refund_id == "re_1"))
    end
  end

  describe "course registrations" do
    setup do
      course = generate(course(name: "Autumn Wreaths", price: "85.00"))

      registration =
        generate(
          course_registration(
            course_id: course.id,
            seats: 2,
            amount: Decimal.new("170.00"),
            payment_intent_id: "pi_course_#{:rand.uniform(1_000_000)}"
          )
        )

      %{registration: registration}
    end

    defp course_succeeded(registration, amount_received) do
      StripeHandler.handle_event(%Stripe.Event{
        id: "evt_course_succeeded",
        type: "payment_intent.succeeded",
        data: %{
          object: %{
            id: registration.payment_intent_id,
            metadata: %{"course_registration_id" => registration.id},
            amount_received: amount_received
          }
        }
      })
    end

    test "confirms the booking and emails a receipt, once", %{registration: registration} do
      assert :ok = course_succeeded(registration, 17_000)
      assert :ok = course_succeeded(registration, 17_000)

      registration = Edenflowers.Courses.get_registration_by_id!(registration.id, authorize?: false)
      assert registration.status == :confirmed
      assert registration.confirmed_at

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)

      assert_email_sent(fn email ->
        assert email.subject =~ "Autumn Wreaths"
        assert [%{content_type: "application/pdf"}] = email.attachments
      end)
    end

    test "records a partial refund from the Stripe dashboard once", %{registration: registration} do
      assert :ok = course_succeeded(registration, 17_000)

      for _redelivery <- 1..2 do
        assert :ok =
                 StripeHandler.handle_event(refund_event("refund.updated", registration.payment_intent_id, "succeeded"))
      end

      payments =
        Edenflowers.Courses.get_registration_by_id!(registration.id, authorize?: false, load: [:payments]).payments

      assert [%{stripe_refund_id: "re_1", method: :stripe} = refund] =
               Enum.filter(payments, &Decimal.negative?(&1.amount))

      assert Decimal.equal?(refund.amount, "-5.00")
    end
  end
end
