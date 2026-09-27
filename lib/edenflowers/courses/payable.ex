defmodule Edenflowers.Courses.Payable do
  @moduledoc "A course booking, as `Edenflowers.Payments` takes payment for it."

  @behaviour Edenflowers.Payments.Payable

  import Edenflowers.Actors

  alias Edenflowers.Courses

  @impl true
  def metadata_key, do: "course_registration_id"

  @impl true
  def expected_amount(registration), do: registration.amount

  # Customers never update a booking, so only the system actor may store the id.
  @impl true
  def add_payment_intent_id(registration, payment_intent_id, _actor) do
    Courses.add_registration_payment_intent_id(registration, payment_intent_id, actor: system_actor())
  end

  @impl true
  def complete(id, payment_intent_id, amount_paid) do
    Courses.confirm_registration_payment(id, payment_intent_id, %{amount_paid: amount_paid}, actor: system_actor())
  end

  # An unpaid booking needs no update: its seat hold simply lapses.
  @impl true
  def fail(_id, _payment_intent_id), do: {:ok, :unchanged}

  @impl true
  def awaiting_payment(settled_before, abandoned_before) do
    Courses.list_registrations_awaiting_payment!(settled_before, abandoned_before, actor: system_actor())
  end
end
