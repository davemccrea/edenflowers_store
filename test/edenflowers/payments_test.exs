defmodule Edenflowers.PaymentsTest do
  use Edenflowers.DataCase

  import ExUnit.CaptureLog
  import Generator
  import Mox

  alias Edenflowers.Courses

  alias Edenflowers.Courses.Workers.SendConfirmationEmail,
    as: SendCourseConfirmationEmail

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Workers.SendConfirmationEmail, as: SendOrderConfirmationEmail
  alias Edenflowers.Payments

  setup :verify_on_exit!

  setup do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id, subscribable: true, free_delivery: true))
    product_variant = generate(product_variant(product_id: product.id))
    fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate.id))

    %{fulfillment_fee: fulfillment_fee} = Edenflowers.Fulfillment.Fee.calculate(fulfillment_option, 0)

    {:ok, user} =
      Edenflowers.Accounts.upsert_user("john.smith@example.com", "John Smith", authorize?: false)

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
    order = Ash.get!(Order, seeded.id, load: [:grand_total], authorize?: false)

    registration =
      generate(
        course_registration(
          amount: Decimal.new("170.00"),
          seats: 2,
          payment_intent_id: "pi_course_#{System.unique_integer([:positive])}"
        )
      )

    %{order: order, registration: registration, product_variant: product_variant}
  end

  defp order_intent(order, amount_received \\ nil) do
    %{
      id: order.payment_intent_id,
      status: "succeeded",
      metadata: %{"order_id" => order.id},
      amount_received: amount_received || StripeAPI.to_stripe_amount(order.grand_total)
    }
  end

  defp course_intent(registration, amount_received \\ 17_000) do
    %{
      id: registration.payment_intent_id,
      status: "succeeded",
      metadata: %{"course_registration_id" => registration.id},
      amount_received: amount_received
    }
  end

  describe "setup/2" do
    test "creates a PaymentIntent for an order's grand total and stores its id", %{order: order} do
      Edenflowers.Repo.query!("UPDATE orders SET payment_intent_id = NULL WHERE id = $1", [Ecto.UUID.dump!(order.id)])
      order = Ash.get!(Order, order.id, load: [:grand_total], authorize?: false)
      expected_cents = StripeAPI.to_stripe_amount(order.grand_total)
      order_id = order.id

      expect(StripeAPI.Mock, :create_payment_intent, fn ^expected_cents, %{"order_id" => ^order_id} ->
        {:ok, %{id: "pi_new", client_secret: "pi_new_secret", amount: expected_cents}}
      end)

      assert {:ok, updated, "pi_new_secret"} = Payments.setup(order, nil)
      assert updated.payment_intent_id == "pi_new"
    end

    test "creates a PaymentIntent for a course booking's amount", %{registration: registration} do
      registration = generate(course_registration(amount: registration.amount, payment_intent_id: nil))
      registration_id = registration.id

      expect(StripeAPI.Mock, :create_payment_intent, fn 17_000, %{"course_registration_id" => ^registration_id} ->
        {:ok, %{id: "pi_course_new", client_secret: "pi_course_secret", amount: 17_000}}
      end)

      assert {:ok, updated, "pi_course_secret"} = Payments.setup(registration, nil)
      assert updated.payment_intent_id == "pi_course_new"
    end

    test "retrieves an existing PaymentIntent", %{order: order} do
      expect(StripeAPI.Mock, :retrieve_payment_intent, fn ^order ->
        {:ok, %{id: order.payment_intent_id, client_secret: "pi_existing_secret"}}
      end)

      assert {:ok, ^order, "pi_existing_secret"} = Payments.setup(order, nil)
    end

    test "replaces a one-off PaymentIntent when the cart becomes a subscription", %{
      order: order,
      product_variant: product_variant
    } do
      Orders.add_line_item!(order.id, product_variant.id, 1, %{interval_weeks: 2}, authorize?: false)
      order = Orders.get_order_for_checkout!(order.id, actor: nil)
      old_intent = %{id: order.payment_intent_id, client_secret: "old_secret", setup_future_usage: nil}
      order_id = order.id

      expect(StripeAPI.Mock, :retrieve_payment_intent, fn ^order -> {:ok, old_intent} end)
      expect(StripeAPI.Mock, :cancel_payment_intent, fn ^old_intent -> {:ok, %{id: old_intent.id}} end)

      expect(StripeAPI.Mock, :create_customer, fn %{email: "john.smith@example.com", name: "John Smith"} ->
        {:ok, %{id: "cus_subscription"}}
      end)

      expect(StripeAPI.Mock, :create_payment_intent_saving_card, fn _amount,
                                                                    %{"order_id" => ^order_id},
                                                                    "cus_subscription" ->
        {:ok, %{id: "pi_subscription", client_secret: "subscription_secret", amount: 0}}
      end)

      assert {:ok, updated, "subscription_secret"} = Payments.setup(order, nil)
      assert updated.payment_intent_id == "pi_subscription"
    end

    test "replaces a card-saving PaymentIntent when the cart becomes one-off", %{
      order: order,
      product_variant: product_variant
    } do
      Orders.add_line_item!(order.id, product_variant.id, 1, %{interval_weeks: 2}, authorize?: false)
      Orders.add_line_item!(order.id, product_variant.id, 1, authorize?: false)
      order = Orders.get_order_for_checkout!(order.id, actor: nil)
      old_intent = %{id: order.payment_intent_id, client_secret: "old_secret", setup_future_usage: "off_session"}
      order_id = order.id

      expect(StripeAPI.Mock, :retrieve_payment_intent, fn ^order -> {:ok, old_intent} end)
      expect(StripeAPI.Mock, :cancel_payment_intent, fn ^old_intent -> {:ok, %{id: old_intent.id}} end)

      expect(StripeAPI.Mock, :create_payment_intent, fn _amount, %{"order_id" => ^order_id} ->
        {:ok, %{id: "pi_one_off", client_secret: "one_off_secret", amount: 0}}
      end)

      assert {:ok, updated, "one_off_secret"} = Payments.setup(order, nil)
      assert updated.payment_intent_id == "pi_one_off"
    end

    test "returns an error when Stripe fails", %{order: order} do
      expect(StripeAPI.Mock, :create_payment_intent, fn _amount, _metadata -> {:error, :network_error} end)
      expect(StripeAPI.Mock, :retrieve_payment_intent, fn _order -> {:error, :not_found} end)

      capture_log(fn ->
        assert {:error, :payment_intent_create_failed} = Payments.setup(%{order | payment_intent_id: nil}, nil)
        assert {:error, :payment_intent_retrieve_failed} = Payments.setup(order, nil)
      end)
    end

    test "cancels the PaymentIntent when its id can't be stored" do
      order = %{generate(order(state: :placed)) | grand_total: Decimal.new("50.00")}
      payment_intent = %{id: "pi_orphan", client_secret: "pi_orphan_secret", amount: 0}

      expect(StripeAPI.Mock, :create_payment_intent, fn _amount, _metadata -> {:ok, payment_intent} end)
      expect(StripeAPI.Mock, :cancel_payment_intent, fn ^payment_intent -> {:ok, %{id: "pi_orphan"}} end)

      capture_log(fn ->
        assert {:error, :payment_intent_persist_failed} = Payments.setup(order, nil)
      end)
    end

    test "a stale record cannot replace an existing PaymentIntent", %{order: order, registration: registration} do
      expect(StripeAPI.Mock, :create_payment_intent, 2, fn _amount, metadata ->
        id = if metadata["order_id"], do: "pi_stale_order", else: "pi_stale_course"
        {:ok, %{id: id, client_secret: "secret", amount: 0}}
      end)

      expect(StripeAPI.Mock, :cancel_payment_intent, 2, fn payment_intent ->
        {:ok, payment_intent}
      end)

      capture_log(fn ->
        assert {:error, :payment_intent_persist_failed} = Payments.setup(%{order | payment_intent_id: nil}, nil)

        assert {:error, :payment_intent_persist_failed} =
                 Payments.setup(%{registration | payment_intent_id: nil}, nil)
      end)

      assert Orders.get_order_by_id!(order.id, authorize?: false).payment_intent_id == order.payment_intent_id

      assert Courses.get_registration_by_id!(registration.id, authorize?: false).payment_intent_id ==
               registration.payment_intent_id
    end
  end

  describe "complete/1" do
    test "places the order and enqueues its confirmation, once", %{order: order} do
      assert {:ok, :completed} = Payments.complete(order_intent(order))
      assert {:ok, :already_completed} = Payments.complete(order_intent(order))

      assert %{state: :placed, payment_status: :paid} =
               Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])

      assert [_job] = all_enqueued(worker: SendOrderConfirmationEmail, args: %{"primary_key" => %{"id" => order.id}})
    end

    test "places an order the customer stepped back from while paying", %{order: order} do
      Orders.return_to_delivery!(order, authorize?: false)

      assert {:ok, :completed} = Payments.complete(order_intent(order))

      assert %{state: :placed, payment_status: :paid} =
               Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])
    end

    test "places an order whose cart was reset while its payment was in flight", %{order: order} do
      Orders.restart_checkout!(order, authorize?: false)

      log = capture_log(fn -> assert {:ok, :completed} = Payments.complete(order_intent(order)) end)

      assert log =~ "Amount mismatch"

      assert %{state: :placed, payment_status: :paid, customer_email: "john.smith@example.com"} =
               Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])
    end

    test "places the order and flags an amount mismatch", %{order: order} do
      paid_cents = StripeAPI.to_stripe_amount(order.grand_total) - 1

      log = capture_log(fn -> assert {:ok, :completed} = Payments.complete(order_intent(order, paid_cents)) end)

      assert log =~ "Amount mismatch"
      order = Orders.get_order_by_id!(order.id, authorize?: false, load: [:amount_mismatch?, :amount_paid])
      assert order.amount_mismatch?
      assert Decimal.equal?(order.amount_paid, Decimal.div(paid_cents, 100))
    end

    test "confirms the course booking and enqueues its confirmation", %{registration: registration} do
      assert {:ok, :completed} = Payments.complete(course_intent(registration))

      assert Courses.get_registration_by_id!(registration.id, authorize?: false).status == :confirmed

      assert_enqueued(
        worker: SendCourseConfirmationEmail,
        args: %{"primary_key" => %{"id" => registration.id}}
      )
    end

    test "rejects course underpayments and overpayments without confirming or enqueueing", %{registration: registration} do
      for amount <- [8_500, 17_001] do
        assert {:error, {:amount_mismatch, id, _expected, _actual}} =
                 Payments.complete(course_intent(registration, amount))

        assert id == registration.id
      end

      assert %{status: :pending, confirmed_at: nil} =
               Courses.get_registration_by_id!(registration.id, authorize?: false)

      refute_enqueued(worker: SendCourseConfirmationEmail)
    end

    test "course confirmation requires the received amount", %{registration: registration} do
      assert {:error, %Ash.Error.Invalid{}} =
               Courses.confirm_registration_payment(registration, registration.payment_intent_id,
                 actor: Edenflowers.Actors.system_actor()
               )

      assert Courses.get_registration_by_id!(registration.id, authorize?: false).status == :pending
      refute_enqueued(worker: SendCourseConfirmationEmail)
    end

    test "order completion rejects invalid currency amounts", %{order: order} do
      for amount <- ["-1.00", "1.001"] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Orders.finalize_checkout(order, order.payment_intent_id, %{amount_paid: amount},
                   actor: Edenflowers.Actors.system_actor()
                 )
      end

      assert %{state: :payment, payment_status: :pending} =
               Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])
    end

    test "a stale order cannot complete twice or replace its reference", %{order: order} do
      assert {:ok, :completed} = Payments.complete(order_intent(order))
      placed = Orders.get_order_by_id!(order.id, authorize?: false)

      assert {:error, error} =
               Orders.finalize_checkout(order, order.payment_intent_id, %{amount_paid: order.grand_total},
                 actor: Edenflowers.Actors.system_actor()
               )

      # Placing the order cleared its PaymentIntent, so the stale one no longer matches.
      assert Enum.any?(error.errors, &is_struct(&1, Payments.Errors.PaymentIntentMismatch))
      current = Orders.get_order_by_id!(order.id, authorize?: false)
      assert current.order_reference == placed.order_reference
      assert current.ordered_at == placed.ordered_at
      assert [_job] = all_enqueued(worker: SendOrderConfirmationEmail, args: %{"primary_key" => %{"id" => order.id}})
    end

    test "rolls back both kinds of completion when enqueue fails, then allows retry", %{
      order: order,
      registration: registration
    } do
      # Oban recognizes this constraint name and returns {:error, changeset}.
      # The sandbox rolls back the test-only constraint along with the data.
      Edenflowers.Repo.query!("ALTER TABLE oban_jobs ADD CONSTRAINT priority_range CHECK (false) NOT VALID")

      for intent <- [order_intent(order), course_intent(registration)] do
        assert {:error, {:payment_update_failed, _id, error}} = Payments.complete(intent)
        assert inspect(error) =~ "enqueue_failed"
      end

      unchanged_order = Orders.get_order_by_id!(order.id, authorize?: false, load: [:amount_paid, :payment_status])
      assert unchanged_order.state == :payment
      assert unchanged_order.payment_status == :pending
      assert unchanged_order.order_reference == order.order_reference
      assert is_nil(unchanged_order.ordered_at)
      assert is_nil(unchanged_order.amount_paid)
      assert is_nil(unchanged_order.vat_breakdown)

      assert %{status: :pending, confirmed_at: nil} =
               Courses.get_registration_by_id!(registration.id, authorize?: false)

      refute_enqueued(worker: SendOrderConfirmationEmail)
      refute_enqueued(worker: SendCourseConfirmationEmail)

      Edenflowers.Repo.query!("ALTER TABLE oban_jobs DROP CONSTRAINT priority_range")

      assert {:ok, :completed} = Payments.complete(order_intent(order))
      assert {:ok, :completed} = Payments.complete(course_intent(registration))
      assert_enqueued(worker: SendOrderConfirmationEmail, args: %{"primary_key" => %{"id" => order.id}})

      assert_enqueued(
        worker: SendCourseConfirmationEmail,
        args: %{"primary_key" => %{"id" => registration.id}}
      )
    end

    test "a stale booking cannot be confirmed twice", %{registration: registration} do
      assert {:ok, :completed} = Payments.complete(course_intent(registration))
      confirmed = Courses.get_registration_by_id!(registration.id, authorize?: false)

      assert {:error, error} =
               Courses.confirm_registration_payment(
                 registration,
                 registration.payment_intent_id,
                 %{amount_paid: registration.amount},
                 actor: Edenflowers.Actors.system_actor()
               )

      assert Enum.any?(error.errors, &is_struct(&1, Payments.Errors.AlreadyPaid))
      assert Courses.get_registration_by_id!(registration.id, authorize?: false).confirmed_at == confirmed.confirmed_at

      assert [_job] =
               all_enqueued(
                 worker: SendCourseConfirmationEmail,
                 args: %{"primary_key" => %{"id" => registration.id}}
               )
    end

    test "a stale payment intent cannot confirm either kind of payable", %{order: order, registration: registration} do
      Edenflowers.Repo.query!("UPDATE orders SET payment_intent_id = $1 WHERE id = $2", [
        "pi_replacement_order",
        Ecto.UUID.dump!(order.id)
      ])

      Edenflowers.Repo.query!("UPDATE course_registrations SET payment_intent_id = $1 WHERE id = $2", [
        "pi_replacement_course",
        Ecto.UUID.dump!(registration.id)
      ])

      results = [
        Orders.finalize_checkout(order, order.payment_intent_id, %{amount_paid: order.grand_total},
          actor: Edenflowers.Actors.system_actor()
        ),
        Courses.confirm_registration_payment(
          registration,
          registration.payment_intent_id,
          %{amount_paid: registration.amount},
          actor: Edenflowers.Actors.system_actor()
        )
      ]

      for result <- results do
        assert {:error, error} = result
        assert Enum.any?(error.errors, &is_struct(&1, Payments.Errors.PaymentIntentMismatch))
      end

      assert Orders.get_order_by_id!(order.id, authorize?: false).state == :payment
      assert Courses.get_registration_by_id!(registration.id, authorize?: false).status == :pending
      refute_enqueued(worker: SendOrderConfirmationEmail)
      refute_enqueued(worker: SendCourseConfirmationEmail)
    end

    test "refuses a PaymentIntent that isn't the record's own", %{order: order} do
      intent = %{order_intent(order) | id: "pi_someone_else"}

      assert {:error, {:payment_intent_mismatch, _id, _expected, "pi_someone_else"}} = Payments.complete(intent)
      assert %{state: :payment} = Orders.get_order_by_id!(order.id, authorize?: false)
    end

    test "refuses a PaymentIntent that names nothing it knows" do
      assert {:error, :unknown_payable} = Payments.complete(%{id: "pi_x", metadata: %{}})
      assert {:error, :unknown_payable} = Payments.complete(%{id: "pi_x", metadata: %{"order_id" => ""}})
    end
  end

  describe "cancel/1" do
    test "clears a course PaymentIntent so payment can be retried", %{registration: registration} do
      assert {:ok, registration} = Payments.cancel(course_intent(registration))
      assert registration.payment_intent_id == nil
      assert registration.status == :pending
    end
  end

  describe "reconcile/1" do
    test "completes a course booking whose PaymentIntent succeeded", %{registration: registration} do
      expect(StripeAPI.Mock, :retrieve_payment_intent, fn _registration -> {:ok, course_intent(registration)} end)

      assert {:ok, :completed} = Payments.reconcile(registration)
      assert Courses.get_registration_by_id!(registration.id, authorize?: false).status == :confirmed
    end

    test "leaves an order whose PaymentIntent hasn't succeeded", %{order: order} do
      expect(StripeAPI.Mock, :retrieve_payment_intent, fn _order ->
        {:ok, %{order_intent(order) | status: "requires_payment_method"}}
      end)

      assert {:ok, :not_succeeded} = Payments.reconcile(order)
      assert %{state: :payment} = Orders.get_order_by_id!(order.id, authorize?: false)
    end
  end
end
