defmodule Edenflowers.Courses.CourseRegistration.Actions.PrepareCheckoutPayment do
  @moduledoc """
  Readies the PaymentIntent of a booking being paid on the course page, at
  its current price less what its Gift voucher will pay. Refuses, with
  `Payments.Errors.NotPayable`, a course that has closed or no longer has
  room for its places: nothing has been paid yet, so they're stopped here
  rather than booked over capacity.

  A booking its voucher pays for in full has nothing for Stripe: it's
  confirmed here, and the result has no client secret.

  The registration's unguessable id is the access, as on the course page.
  Bookings never use saved cards, so there's no customer actor.
  """

  use Ash.Resource.Actions.Implementation

  import Edenflowers.Actors

  alias Edenflowers.Courses
  alias Edenflowers.Payments
  alias Edenflowers.Payments.Errors.NotPayable

  @impl true
  def run(input, _opts, _context) do
    with {:ok, registration} <-
           Courses.get_checkout_registration(input.arguments.registration_id, input.arguments.course_id,
             actor: system_actor(),
             load: [:stripe_amount, course: [:booking_open?, :seats_left]]
           ),
         :ok <- bookable(registration) do
      pay(registration)
    end
  end

  defp bookable(%{course: course, seats: seats}) do
    cond do
      not course.booking_open? -> {:error, NotPayable.exception(reason: :booking_closed)}
      seats > course.seats_left -> {:error, NotPayable.exception(reason: :not_enough_places)}
      true -> :ok
    end
  end

  defp pay(registration) do
    if Decimal.positive?(registration.stripe_amount) do
      with {:ok, registration, client_secret} <- Payments.prepare(registration, nil) do
        {:ok, %{payable: registration, client_secret: client_secret}}
      end
    else
      with {:ok, registration} <- Courses.confirm_registration_paid_by_voucher(registration, actor: system_actor()) do
        {:ok, %{payable: registration, client_secret: nil}}
      end
    end
  end
end
