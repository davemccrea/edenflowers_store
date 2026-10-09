defmodule EdenflowersWeb.Webhooks.StripeHandlerTest do
  use Edenflowers.DataCase, async: true

  import ExUnit.CaptureLog
  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Orders.Order

  alias Edenflowers.Orders

  setup do
    Edenflowers.Repo.delete_all(Oban.Job)

    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    product_variant = generate(product_variant(product_id: product.id))
    fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate.id))

    %{fulfillment_fee: fulfillment_fee} = Edenflowers.Fulfillment.Fee.calculate(fulfillment_option, 0)

    {:ok, user} =
      Edenflowers.Accounts.upsert_user("john.smith@example.com", "John Smith", authorize?: false)

    order =
      Ash.Seed.seed!(Order, %{
        order_reference: :crypto.strong_rand_bytes(6) |> Base.encode16(),
        state: :payment,
        customer_name: "John Smith",
        customer_email: "john.smith@example.com",
        user_id: user.id,
        fulfillment_option_id: fulfillment_option.id,
        fulfillment_date: Date.utc_today(),
        quoted_fulfillment_fee: fulfillment_fee,
        payment_intent_id: "pi_test_#{:rand.uniform(1_000_000)}"
      })

    generate(
      line_item(
        order_id: order.id,
        product_variant_id: product_variant.id,
        quantity: 1
      )
    )

    # Derive the expected Stripe amount from the order's real grand_total via the
    # same conversion the handler uses, so the fixture can't silently diverge from
    # production's rounding.
    %{grand_total: grand_total} = Ash.get!(Order, order.id, load: [:grand_total], authorize?: false)
    expected_amount = Edenflowers.External.StripeAPI.to_stripe_amount(grand_total)

    %{order: order, expected_amount: expected_amount}
  end

  describe "setup_intent.succeeded" do
    test "stores the new card and returns a held subscription to active", %{order: order} do
      subscription = subscription(order, :payment_failed)

      assert :ok = EdenflowersWeb.Webhooks.StripeHandler.handle_event(setup_intent_succeeded(subscription))

      assert %{state: :active, stripe_payment_method_id: "pm_new"} = Ash.reload!(subscription, authorize?: false)
    end

    @tag capture_log: true
    test "acknowledges a card saved to a cancelled subscription, so Stripe stops retrying", %{order: order} do
      subscription = subscription(order, :cancelled)

      assert :ok = EdenflowersWeb.Webhooks.StripeHandler.handle_event(setup_intent_succeeded(subscription))

      assert %{state: :cancelled, stripe_payment_method_id: "pm_old"} = Ash.reload!(subscription, authorize?: false)
    end

    defp subscription(order, state) do
      Ash.Seed.seed!(Edenflowers.Orders.Subscription, %{
        user_id: order.user_id,
        product_variant_id:
          Ash.load!(order, :line_items, authorize?: false).line_items |> hd() |> Map.get(:product_variant_id),
        fulfillment_option_id: order.fulfillment_option_id,
        interval_weeks: 2,
        next_fulfillment_date: Date.add(Date.utc_today(), 10),
        locale: "en",
        state: state,
        stripe_customer_id: "cus_1",
        stripe_payment_method_id: "pm_old"
      })
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
               EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
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

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)

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
      assert :ok = EdenflowersWeb.Webhooks.StripeHandler.handle_event(event)
      # Stripe redelivers the same event after we've already processed it. The
      # handler must still return :ok so Stripe stops retrying, and the receipt_emailed_at
      # guard in the worker prevents a duplicate send.
      assert :ok = EdenflowersWeb.Webhooks.StripeHandler.handle_event(event)

      order = Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])
      assert order.state == :placed
      assert order.payment_status == :paid

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)
    end

    test "places the order and flags the mismatch when amount_received does not match grand_total", %{
      order: order,
      expected_amount: expected_amount
    } do
      log =
        capture_log(fn ->
          assert :ok =
                   EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
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
        Orders.get_order_by_id!(order.id, authorize?: false, load: [:amount_mismatch?, :amount_paid, :payment_status])

      assert order.state == :placed
      assert order.payment_status == :pending
      assert Decimal.equal?(order.amount_paid, Decimal.div(expected_amount - 1, 100))
      assert order.amount_mismatch?
    end

    test "logs error and returns :ok when payment_intent_id does not match", %{
      order: order,
      expected_amount: expected_amount
    } do
      log =
        capture_log(fn ->
          assert :ok =
                   EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
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
                 EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
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
    test "leaves the order in checkout for the customer to retry", %{order: order} do
      assert :ok =
               EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
                 id: "evt_failed_1",
                 type: "payment_intent.payment_failed",
                 data: %{object: %{id: order.payment_intent_id, metadata: %{"order_id" => order.id}}}
               })

      order = Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])
      assert order.state == :payment
      assert order.payment_status == :pending

      refute_email_sent()
    end

    test "does not downgrade an already-paid order", %{order: order, expected_amount: expected_amount} do
      # Succeeded fires first.
      assert :ok =
               EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
                 id: "evt_first_success",
                 type: "payment_intent.succeeded",
                 data: %{
                   object: %{
                     id: order.payment_intent_id,
                     metadata: %{"order_id" => order.id},
                     amount_received: expected_amount
                   }
                 }
               })

      # A late `payment_failed` for the same intent shouldn't flip the order back.
      assert :ok =
               EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
                 id: "evt_late_failure",
                 type: "payment_intent.payment_failed",
                 data: %{object: %{id: order.payment_intent_id, metadata: %{"order_id" => order.id}}}
               })

      order = Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])
      assert order.state == :placed
      assert order.payment_status == :paid
    end
  end

  describe "payment_intent.canceled" do
    test "clears the canceled intent so the order can open a fresh one", %{order: order} do
      assert :ok =
               EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
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
    test "returns :ok for charge.succeeded (handled via payment_intent.succeeded)" do
      assert :ok =
               EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
                 id: "evt_charge_succeeded",
                 type: "charge.succeeded",
                 data: %{object: %{}}
               })
    end

    test "returns :ok for an unhandled event type" do
      capture_log(fn ->
        assert :ok =
                 EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
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
      EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
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

  describe "a refund made in the Stripe dashboard" do
    setup %{order: order, expected_amount: expected_amount} do
      payment_intent_id = order.payment_intent_id

      assert :ok =
               EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
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
      assert :ok = EdenflowersWeb.Webhooks.StripeHandler.handle_event(refund_event("refund.created", pi, "pending"))
      assert [] = refunds(order)

      assert :ok = EdenflowersWeb.Webhooks.StripeHandler.handle_event(refund_event("refund.updated", pi, "succeeded"))
      assert :ok = EdenflowersWeb.Webhooks.StripeHandler.handle_event(refund_event("refund.updated", pi, "succeeded"))

      assert [refund] = refunds(order)
      assert Decimal.equal?(refund.amount, "-5.00")
      assert refund.stripe_refund_id == "re_1"
    end

    test "is never recorded when a pending refund fails", %{order: order, payment_intent_id: pi} do
      balance_before = Orders.get_order_by_id!(order.id, authorize?: false, load: [:balance]).balance

      assert :ok = EdenflowersWeb.Webhooks.StripeHandler.handle_event(refund_event("refund.created", pi, "pending"))
      assert :ok = EdenflowersWeb.Webhooks.StripeHandler.handle_event(refund_event("refund.updated", pi, "failed"))

      assert [] = refunds(order)
      balance_after = Orders.get_order_by_id!(order.id, authorize?: false, load: [:balance]).balance
      assert Decimal.equal?(balance_after, balance_before)
    end

    test "of a payment the shop doesn't know is ignored" do
      assert :ok =
               EdenflowersWeb.Webhooks.StripeHandler.handle_event(
                 refund_event("refund.created", "pi_course", "succeeded")
               )
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
      EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
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

    test "logs and acknowledges a mismatched amount without confirming the booking", %{registration: registration} do
      log = capture_log(fn -> assert :ok = course_succeeded(registration, 8_500) end)

      assert log =~ "amount mismatch"
      assert Edenflowers.Courses.get_registration_by_id!(registration.id, authorize?: false).status == :pending

      refute_enqueued(worker: Edenflowers.Courses.Workers.SendConfirmationEmail)
    end

    test "ignores a failed payment; the seat hold lapses on its own", %{registration: registration} do
      assert :ok =
               EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
                 id: "evt_course_failed",
                 type: "payment_intent.payment_failed",
                 data: %{
                   object: %{
                     id: registration.payment_intent_id,
                     metadata: %{"course_registration_id" => registration.id}
                   }
                 }
               })

      assert Edenflowers.Courses.get_registration_by_id!(registration.id, authorize?: false).status == :pending
    end
  end
end
