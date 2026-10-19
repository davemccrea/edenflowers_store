defmodule Edenflowers.PaymentsTest do
  # Sync because a test adds a CHECK (false) constraint to oban_jobs, and ALTER TABLE locks it for every test
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
  alias Edenflowers.Orders.Workers.SendReceiptEmail
  alias Edenflowers.Payments

  setup :verify_on_exit!

  setup do
    product = generate(product(subscribable: true, free_delivery: true))
    product_variant = generate(product_variant(product_id: product.id))
    order = order_in_payment(product_variant_id: product_variant.id)

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

  defp john, do: Edenflowers.Accounts.get_user_by_email!("john.smith@example.com", authorize?: false)

  defp without_payment_intent(order) do
    Edenflowers.Repo.query!("UPDATE orders SET payment_intent_id = NULL WHERE id = $1", [Ecto.UUID.dump!(order.id)])
    Orders.get_order_for_checkout!(order.id, actor: nil)
  end

  defp missing_customer_error do
    %Stripe.Error{
      source: :stripe,
      code: :invalid_request_error,
      message: "No such customer: 'cus_deleted'",
      extra: %{raw_error: %{"code" => "resource_missing", "param" => "customer"}}
    }
  end

  describe "customer_session/2" do
    test "leaves saved cards out when Stripe can't make a CustomerSession", %{order: order} do
      user = Ash.Seed.update!(john(), %{stripe_customer_id: "cus_john"})

      expect(StripeAPI.Mock, :create_customer_session, fn "cus_john" -> {:error, :network_error} end)

      capture_log(fn -> assert Payments.customer_session(order, user) == nil end)
      assert Ash.reload!(user, authorize?: false).stripe_customer_id == "cus_john"
    end

    test "forgets a Customer deleted in Stripe", %{order: order} do
      user = Ash.Seed.update!(john(), %{stripe_customer_id: "cus_deleted"})

      expect(StripeAPI.Mock, :create_customer_session, fn "cus_deleted" -> {:error, missing_customer_error()} end)

      capture_log(fn -> assert Payments.customer_session(order, user) == nil end)
      assert Ash.reload!(user, authorize?: false).stripe_customer_id == nil
    end
  end

  describe "setup/2" do
    test "creates a PaymentIntent for an order's grand total and stores its id", %{order: order} do
      Edenflowers.Repo.query!("UPDATE orders SET payment_intent_id = NULL WHERE id = $1", [Ecto.UUID.dump!(order.id)])
      order = Ash.get!(Order, order.id, load: [:grand_total], authorize?: false)
      expected_cents = StripeAPI.to_stripe_amount(order.grand_total)
      order_id = order.id

      expect(StripeAPI.Mock, :create_payment_intent, fn ^expected_cents, %{"order_id" => ^order_id}, _customer ->
        {:ok, %{id: "pi_new", client_secret: "pi_new_secret", amount: expected_cents}}
      end)

      assert {:ok, updated, "pi_new_secret"} = Payments.setup(order, nil)
      assert updated.payment_intent_id == "pi_new"
    end

    test "a signed-in customer's PaymentIntent and CustomerSession carry their own Customer; a guest's carry none",
         %{order: order} do
      order = without_payment_intent(order)
      user = john()

      expect(StripeAPI.Mock, :create_customer, fn %{email: "john.smith@example.com"} -> {:ok, %{id: "cus_john"}} end)

      expect(StripeAPI.Mock, :create_payment_intent, fn _amount, _metadata, "cus_john" ->
        {:ok, %{id: "pi_john", client_secret: "pi_john_secret", amount: 0}}
      end)

      expect(StripeAPI.Mock, :create_customer_session, fn "cus_john" -> {:ok, %{client_secret: "cuss_john"}} end)

      assert {:ok, order, "pi_john_secret"} = Payments.setup(order, user)
      assert Payments.customer_session(order, user) == "cuss_john"

      order = without_payment_intent(order)

      expect(StripeAPI.Mock, :create_payment_intent, fn _amount, _metadata, nil ->
        {:ok, %{id: "pi_guest", client_secret: "pi_guest_secret", amount: 0}}
      end)

      assert {:ok, order, "pi_guest_secret"} = Payments.setup(order, nil)
      assert Payments.customer_session(order, nil) == nil
    end

    test "creates a signed-in customer's Customer once and reuses it", %{order: order} do
      user = john()

      expect(StripeAPI.Mock, :create_customer, 1, fn _params -> {:ok, %{id: "cus_john"}} end)

      expect(StripeAPI.Mock, :create_payment_intent, 2, fn _amount, _metadata, "cus_john" ->
        {:ok, %{id: "pi_john_#{System.unique_integer([:positive])}", client_secret: "pi_john_secret", amount: 0}}
      end)

      # The same stale user both times, as the checkout's socket holds it.
      assert {:ok, order, _secret} = Payments.setup(without_payment_intent(order), user)
      assert {:ok, _order, _secret} = Payments.setup(without_payment_intent(order), user)
    end

    test "a signed-in customer's subscription gets a Customer of its own and no CustomerSession", %{
      order: order,
      product_variant: product_variant
    } do
      Orders.add_line_item!(order.id, product_variant.id, 1, %{interval_weeks: 2}, authorize?: false)
      order = without_payment_intent(order)
      user = john()

      expect(StripeAPI.Mock, :create_customer, 1, fn _params -> {:ok, %{id: "cus_subscription"}} end)

      expect(StripeAPI.Mock, :create_payment_intent_saving_card, fn _amount, _metadata, "cus_subscription" ->
        {:ok, %{id: "pi_subscription", client_secret: "subscription_secret", amount: 0}}
      end)

      assert {:ok, order, "subscription_secret"} = Payments.setup(order, user)
      assert Payments.customer_session(order, user) == nil
      assert Ash.reload!(user, authorize?: false).stripe_customer_id == nil
    end

    test "replaces a PaymentIntent opened before the customer signed in", %{order: order} do
      user = john()
      Ash.Seed.update!(user, %{stripe_customer_id: "cus_john"})
      order = Orders.get_order_for_checkout!(order.id, actor: nil)
      guest_intent = %{id: order.payment_intent_id, client_secret: "guest_secret", customer: nil}

      expect(StripeAPI.Mock, :retrieve_payment_intent, fn ^order -> {:ok, guest_intent} end)
      expect(StripeAPI.Mock, :cancel_payment_intent, fn ^guest_intent -> {:ok, guest_intent} end)

      expect(StripeAPI.Mock, :create_payment_intent, fn _amount, _metadata, "cus_john" ->
        {:ok, %{id: "pi_john", client_secret: "pi_john_secret", amount: 0}}
      end)

      assert {:ok, _order, "pi_john_secret"} = Payments.setup(order, user)
    end

    test "replaces a PaymentIntent left on a customer's Customer after they signed out", %{order: order} do
      order = Orders.get_order_for_checkout!(order.id, actor: nil)
      johns_intent = %{id: order.payment_intent_id, client_secret: "john_secret", customer: "cus_john"}

      expect(StripeAPI.Mock, :retrieve_payment_intent, fn ^order -> {:ok, johns_intent} end)
      expect(StripeAPI.Mock, :cancel_payment_intent, fn ^johns_intent -> {:ok, johns_intent} end)

      expect(StripeAPI.Mock, :create_payment_intent, fn _amount, _metadata, nil ->
        {:ok, %{id: "pi_guest", client_secret: "pi_guest_secret", amount: 0}}
      end)

      assert {:ok, _order, "pi_guest_secret"} = Payments.setup(order, nil)
    end

    test "forgets a Customer deleted in Stripe and takes the payment without it", %{order: order} do
      order = without_payment_intent(order)
      user = Ash.Seed.update!(john(), %{stripe_customer_id: "cus_deleted"})

      expect(StripeAPI.Mock, :create_payment_intent, fn _amount, _metadata, "cus_deleted" ->
        {:error, missing_customer_error()}
      end)

      expect(StripeAPI.Mock, :create_payment_intent, fn _amount, _metadata, nil ->
        {:ok, %{id: "pi_no_customer", client_secret: "pi_no_customer_secret", amount: 0}}
      end)

      capture_log(fn ->
        assert {:ok, _order, "pi_no_customer_secret"} = Payments.setup(order, user)
      end)

      assert Ash.reload!(user, authorize?: false).stripe_customer_id == nil
    end

    test "creates a PaymentIntent for a course booking's amount", %{registration: registration} do
      registration = generate(course_registration(amount: registration.amount, payment_intent_id: nil))
      registration_id = registration.id

      expect(StripeAPI.Mock, :create_payment_intent, fn 17_000,
                                                        %{"course_registration_id" => ^registration_id},
                                                        _customer ->
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

      expect(StripeAPI.Mock, :create_payment_intent, fn _amount, %{"order_id" => ^order_id}, _customer ->
        {:ok, %{id: "pi_one_off", client_secret: "one_off_secret", amount: 0}}
      end)

      assert {:ok, updated, "one_off_secret"} = Payments.setup(order, nil)
      assert updated.payment_intent_id == "pi_one_off"
    end

    test "returns an error when Stripe fails", %{order: order} do
      expect(StripeAPI.Mock, :create_payment_intent, fn _amount, _metadata, _customer -> {:error, :network_error} end)
      expect(StripeAPI.Mock, :retrieve_payment_intent, fn _order -> {:error, :not_found} end)

      capture_log(fn ->
        assert {:error, :payment_intent_create_failed} = Payments.setup(%{order | payment_intent_id: nil}, nil)
        assert {:error, :payment_intent_retrieve_failed} = Payments.setup(order, nil)
      end)
    end

    test "cancels the PaymentIntent when its id can't be stored" do
      order = %{generate(order(state: :placed)) | grand_total: Decimal.new("50.00")}
      payment_intent = %{id: "pi_orphan", client_secret: "pi_orphan_secret", amount: 0}

      expect(StripeAPI.Mock, :create_payment_intent, fn _amount, _metadata, _customer -> {:ok, payment_intent} end)
      expect(StripeAPI.Mock, :cancel_payment_intent, fn ^payment_intent -> {:ok, %{id: "pi_orphan"}} end)

      capture_log(fn ->
        assert {:error, :payment_intent_persist_failed} = Payments.setup(order, nil)
      end)
    end

    test "a stale record cannot replace an existing PaymentIntent", %{order: order, registration: registration} do
      expect(StripeAPI.Mock, :create_payment_intent, 2, fn _amount, metadata, _customer ->
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

      assert [_job] = all_enqueued(worker: SendReceiptEmail, args: %{"primary_key" => %{"id" => order.id}})
    end

    test "records the card that paid, for the receipt", %{order: order} do
      expect(StripeAPI.Mock, :retrieve_payment_method, fn "pm_card" ->
        {:ok, %{type: "card", card: %{brand: "visa", last4: "4242"}}}
      end)

      assert {:ok, :completed} = Payments.complete(Map.put(order_intent(order), :payment_method, "pm_card"))

      assert [%{payment_method_type: "card", card_brand: "visa", card_last4: "4242"}] =
               Orders.get_order_by_id!(order.id, authorize?: false, load: [:payments]).payments
    end

    test "records a payment method that isn't a card by its type", %{order: order} do
      expect(StripeAPI.Mock, :retrieve_payment_method, fn "pm_mobilepay" -> {:ok, %{type: "mobilepay"}} end)

      assert {:ok, :completed} = Payments.complete(Map.put(order_intent(order), :payment_method, "pm_mobilepay"))

      assert [%{payment_method_type: "mobilepay", card_brand: nil}] =
               Orders.get_order_by_id!(order.id, authorize?: false, load: [:payments]).payments
    end

    test "still completes when the payment method can't be looked up", %{order: order} do
      expect(StripeAPI.Mock, :retrieve_payment_method, fn "pm_gone" -> {:error, :timeout} end)

      log =
        capture_log(fn ->
          assert {:ok, :completed} = Payments.complete(Map.put(order_intent(order), :payment_method, "pm_gone"))
        end)

      assert log =~ "Couldn't look up payment method pm_gone"

      assert [%{payment_method_type: nil}] =
               Orders.get_order_by_id!(order.id, authorize?: false, load: [:payments]).payments
    end

    test "records the card that paid for a course booking", %{registration: registration} do
      expect(StripeAPI.Mock, :retrieve_payment_method, fn "pm_card" ->
        {:ok, %{type: "card", card: %{brand: "amex", last4: "0005"}}}
      end)

      assert {:ok, :completed} = Payments.complete(Map.put(course_intent(registration), :payment_method, "pm_card"))

      assert [%{payment_method_type: "card", card_brand: "amex", card_last4: "0005"}] =
               Courses.get_registration_by_id!(registration.id, authorize?: false, load: [:payments]).payments
    end

    test "records a course booking's payment once, however often it completes", %{registration: registration} do
      expect(StripeAPI.Mock, :retrieve_payment_intent, fn _registration -> {:ok, course_intent(registration)} end)

      assert {:ok, :completed} = Payments.complete(course_intent(registration))
      assert {:ok, :already_completed} = Payments.complete(course_intent(registration))
      assert {:ok, :already_completed} = Payments.reconcile(registration)

      payment_intent_id = registration.payment_intent_id

      assert [%{method: :stripe, payment_intent_id: ^payment_intent_id, paid_at: %DateTime{}} = payment] =
               Courses.get_registration_by_id!(registration.id, authorize?: false, load: [:payments]).payments

      assert Decimal.equal?(payment.amount, "170.00")
    end

    test "a paid course booking cancels without touching its spent PaymentIntent", %{registration: registration} do
      assert {:ok, :completed} = Payments.complete(course_intent(registration))

      registration = Courses.get_registration_by_id!(registration.id, authorize?: false)
      assert registration.payment_intent_id == nil

      # Mox fails the test if cancelling calls cancel_payment_intent.
      assert {:ok, %{status: :cancelled}} = Courses.cancel_registration(registration, authorize?: false)
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
      order = Orders.get_order_by_id!(order.id, authorize?: false, load: [:balance, :amount_paid])
      assert Decimal.equal?(order.balance, Decimal.new("0.01"))
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
      assert [_job] = all_enqueued(worker: SendReceiptEmail, args: %{"primary_key" => %{"id" => order.id}})
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
      assert Decimal.eq?(unchanged_order.amount_paid, 0)
      assert is_nil(unchanged_order.vat_breakdown)

      assert %{status: :pending, confirmed_at: nil} =
               Courses.get_registration_by_id!(registration.id, authorize?: false)

      refute_enqueued(worker: SendReceiptEmail)
      refute_enqueued(worker: SendCourseConfirmationEmail)

      Edenflowers.Repo.query!("ALTER TABLE oban_jobs DROP CONSTRAINT priority_range")

      assert {:ok, :completed} = Payments.complete(order_intent(order))
      assert {:ok, :completed} = Payments.complete(course_intent(registration))
      assert_enqueued(worker: SendReceiptEmail, args: %{"primary_key" => %{"id" => order.id}})

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
      refute_enqueued(worker: SendReceiptEmail)
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

  describe "sync_refunds/1" do
    test "records a course booking's refund whose webhook never arrived, once", %{registration: registration} do
      assert {:ok, :completed} = Payments.complete(course_intent(registration))
      payment_intent_id = registration.payment_intent_id

      stub(StripeAPI.Mock, :list_refunds, fn ^payment_intent_id ->
        {:ok, [%{id: "re_missed", payment_intent: payment_intent_id, amount: 8_500, status: "succeeded"}]}
      end)

      assert {:ok, 1} = Payments.sync_refunds(registration)
      assert {:ok, 0} = Payments.sync_refunds(registration)

      assert [_payment, %{stripe_refund_id: "re_missed", amount: amount}] =
               Courses.get_registration_by_id!(registration.id,
                 authorize?: false,
                 load: [payments: Ash.Query.sort(Edenflowers.Payments.Payment, amount: :desc)]
               ).payments

      assert Decimal.equal?(amount, "-85.00")
    end
  end

  describe "refund_balance/1 for a course booking" do
    setup %{registration: registration} do
      assert {:ok, :completed} = Payments.complete(course_intent(registration))
      stub(StripeAPI.Mock, :list_refunds, fn _payment_intent_id -> {:ok, []} end)

      %{
        registration: Courses.get_registration_by_id!(registration.id, authorize?: false),
        pi: registration.payment_intent_id
      }
    end

    defp succeeded_refund(payment_intent_id, cents) do
      %{id: "re_#{cents}", payment_intent: payment_intent_id, amount: cents, status: "succeeded"}
    end

    defp refunds(registration) do
      Courses.get_registration_by_id!(registration.id, authorize?: false, load: [:payments]).payments
      |> Enum.filter(&Decimal.negative?(&1.amount))
    end

    test "refunds a cancelled booking what was paid, once", %{registration: registration, pi: pi} do
      expect(StripeAPI.Mock, :create_refund, fn ^pi, 17_000, _key, _metadata -> {:ok, succeeded_refund(pi, 17_000)} end)

      {:ok, registration} = Courses.cancel_registration(registration, authorize?: false)
      assert {:ok, [_refund]} = Payments.refund_balance(registration)

      # The second click finds the first refund in Stripe.
      stub(StripeAPI.Mock, :list_refunds, fn ^pi -> {:ok, [succeeded_refund(pi, 17_000)]} end)

      assert {:ok, []} = Payments.refund_balance(registration)

      assert [%{amount: amount, method: :stripe}] = refunds(registration)
      assert Decimal.equal?(amount, "-170.00")
    end

    test "refunds one seat's price after a seat is removed", %{registration: registration, pi: pi} do
      expect(StripeAPI.Mock, :create_refund, fn ^pi, 8_500, _key, _metadata -> {:ok, succeeded_refund(pi, 8_500)} end)

      {:ok, registration} = Courses.remove_registration_seat(registration, authorize?: false)
      assert {:ok, [_refund]} = Payments.refund_balance(registration)

      assert [%{amount: amount}] = refunds(registration)
      assert Decimal.equal?(amount, "-85.00")
    end

    test "cancelling refunds nothing by itself", %{registration: registration} do
      {:ok, registration} = Courses.cancel_registration(registration, authorize?: false)

      assert [] = refunds(registration)
      assert Decimal.equal?(Ash.load!(registration, :balance, authorize?: false).balance, "-170.00")
    end
  end

  describe "Payment" do
    test "belongs to exactly one order or course registration", %{order: order, registration: registration} do
      for parents <- [%{}, %{order_id: order.id, course_registration_id: registration.id}] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Edenflowers.Payments.Payment
                 |> Ash.Changeset.for_create(:record, Map.merge(parents, %{amount: "10.00", method: :cash}))
                 |> Ash.create(authorize?: false)
      end
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
