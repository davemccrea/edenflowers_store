defmodule Edenflowers.Courses.PaymentTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Mox

  alias Edenflowers.Courses.Payment

  setup :verify_on_exit!

  test "creates a payment intent for the booking amount and persists its id" do
    registration = generate(course_registration())

    expect(Edenflowers.External.StripeAPI.Mock, :create_course_payment_intent, fn ^registration ->
      {:ok, %{id: "pi_course", client_secret: "pi_course_secret", amount: 8_500}}
    end)

    assert {:ok, updated, "pi_course_secret"} = Payment.setup_payment(registration)
    assert updated.payment_intent_id == "pi_course"
  end

  test "reuses an existing payment intent" do
    registration = generate(course_registration(payment_intent_id: "pi_existing"))

    expect(Edenflowers.External.StripeAPI.Mock, :retrieve_payment_intent, fn ^registration ->
      {:ok, %{id: "pi_existing", client_secret: "pi_existing_secret"}}
    end)

    assert {:ok, ^registration, "pi_existing_secret"} = Payment.setup_payment(registration)
  end
end
