defmodule Edenflowers.Courses.DiscardRegistrationTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Mox

  alias Edenflowers.Actors
  alias Edenflowers.Courses
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Payments

  setup :verify_on_exit!

  test "the destroy action checks a payment attached after the caller loaded the registration" do
    stale = generate(course_registration())
    Courses.add_registration_payment_intent_id!(stale, "pi_processing", actor: Actors.system_actor())
    processing_payment("pi_processing")

    assert {:error, _} = Ash.destroy(stale, action: :discard, actor: Actors.system_actor())
    assert Courses.get_registration_by_id!(stale.id, authorize?: false).payment_intent_id == "pi_processing"
  end

  test "an intent attached after a nil-intent check prevents deletion" do
    registration = generate(course_registration())

    changeset =
      registration
      |> Ash.Changeset.for_destroy(:discard, %{}, actor: Actors.system_actor())
      |> Ash.Changeset.before_action(fn changeset ->
        Courses.add_registration_payment_intent_id!(registration, "pi_new", actor: Actors.system_actor())
        changeset
      end)

    assert {:error, _} = Ash.destroy(changeset)
    assert {:ok, _retained} = Courses.get_registration_by_id(registration.id, authorize?: false)
  end

  test "returns no registration after deletion, including an already absent registration" do
    registration = generate(course_registration())

    assert {:ok, nil} = Courses.discard_registration(registration.id, actor: Actors.system_actor())
    assert {:ok, nil} = Courses.discard_registration(registration.id, actor: Actors.system_actor())
  end

  test "returns the current registration when its payment is processing" do
    registration = generate(course_registration(payment_intent_id: "pi_processing"))
    processing_payment("pi_processing")

    assert {:ok, %{payment_intent_id: "pi_processing", committed?: false}} =
             Courses.discard_registration(registration.id, actor: Actors.system_actor())
  end

  test "a cancellation webhook may clear the checked intent before deletion" do
    registration = generate(course_registration(payment_intent_id: "pi_cancelled"))

    expect(StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_cancelled"} ->
      assert {:ok, _} = Payments.cancel(intent(registration, "pi_cancelled"))
      {:ok, %{status: "canceled"}}
    end)

    assert {:ok, nil} = Courses.discard_registration(registration.id, actor: Actors.system_actor())
    assert {:error, _} = Courses.get_registration_by_id(registration.id, authorize?: false)
  end

  test "a replacement intent attached during cancellation prevents deletion" do
    registration = generate(course_registration(payment_intent_id: "pi_old"))

    expect(StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_old"} ->
      assert {:ok, cleared} = Payments.cancel(intent(registration, "pi_old"))
      Courses.add_registration_payment_intent_id!(cleared, "pi_new", actor: Actors.system_actor())
      {:ok, %{status: "canceled"}}
    end)

    assert {:ok, %{payment_intent_id: "pi_new", committed?: false}} =
             Courses.discard_registration(registration.id, actor: Actors.system_actor())
  end

  test "retains a registration when payment completes during cancellation" do
    registration = generate(course_registration(payment_intent_id: "pi_paid"))

    expect(StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_paid"} ->
      assert {:ok, :completed} = Payments.complete(intent(registration, "pi_paid"))
      {:error, :already_succeeded}
    end)

    expect(StripeAPI.Mock, :retrieve_payment_intent, fn %{payment_intent_id: "pi_paid"} ->
      {:ok, %{status: "succeeded"}}
    end)

    assert {:ok, %{committed?: true}} = Courses.discard_registration(registration.id, actor: Actors.system_actor())
  end

  test "a registration confirmed before discard is returned without cancelling Stripe" do
    registration = generate(course_registration(payment_intent_id: "pi_paid"))
    assert {:ok, :completed} = Payments.complete(intent(registration, "pi_paid"))

    assert {:ok, %{committed?: true}} = Courses.discard_registration(registration.id, actor: Actors.system_actor())
  end

  test "unexpected Stripe failures remain errors and preserve the registration" do
    registration = generate(course_registration(payment_intent_id: "pi_offline"))
    expect(StripeAPI.Mock, :cancel_payment_intent, fn _ -> {:error, :offline} end)
    expect(StripeAPI.Mock, :retrieve_payment_intent, fn _ -> {:error, :offline} end)

    assert {:error, error} = Courses.discard_registration(registration.id, actor: Actors.system_actor())
    assert Exception.message(error) =~ "offline"
    assert {:ok, _} = Courses.get_registration_by_id(registration.id, authorize?: false)
  end

  test "a refusal to cancel an otherwise cancellable intent is an error, not expected retention" do
    registration = generate(course_registration(payment_intent_id: "pi_unpaid"))
    expect(StripeAPI.Mock, :cancel_payment_intent, fn _ -> {:error, :offline} end)

    expect(StripeAPI.Mock, :retrieve_payment_intent, fn _ ->
      {:ok, %{status: "requires_payment_method"}}
    end)

    assert {:error, error} = Courses.discard_registration(registration.id, actor: Actors.system_actor())
    assert Exception.message(error) =~ "offline"
    assert {:ok, _} = Courses.get_registration_by_id(registration.id, authorize?: false)
  end

  test "customers cannot use the operation even for their own registration" do
    customer = generate(admin_user(admin: false))
    registration = generate(course_registration(user_id: customer.id))

    assert {:error, %Ash.Error.Forbidden{}} = Courses.discard_registration(registration.id, actor: customer)
    assert {:ok, _} = Courses.get_registration_by_id(registration.id, authorize?: false)
  end

  @tag capture_log: true
  test "the abandoned-checkout worker also preserves a processing payment" do
    registration =
      generate(
        course_registration(
          payment_intent_id: "pi_processing",
          updated_at: DateTime.add(DateTime.utc_now(), -25, :hour)
        )
      )

    processing_payment("pi_processing")

    assert_raise Ash.Error.Invalid, fn ->
      perform_job(Edenflowers.Courses.Workers.DiscardAbandoned, %{"primary_key" => %{"id" => registration.id}})
    end

    assert {:ok, _} = Ash.get(CourseRegistration, registration.id, authorize?: false)
  end

  defp processing_payment(id) do
    expect(StripeAPI.Mock, :cancel_payment_intent, fn %{id: ^id} -> {:error, :processing} end)
    expect(StripeAPI.Mock, :retrieve_payment_intent, fn %{payment_intent_id: ^id} -> {:ok, %{status: "processing"}} end)
  end

  defp intent(registration, id) do
    %{
      id: id,
      metadata: %{"course_registration_id" => registration.id},
      amount_received: registration.amount |> Decimal.mult(100) |> Decimal.to_integer()
    }
  end
end
