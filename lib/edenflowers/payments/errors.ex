defmodule Edenflowers.Payments.Errors.AlreadyPaid do
  @moduledoc """
  Returned when an action would record a payment, or a failed payment, for
  something already paid. Stripe delivers webhooks at least once, so
  `Edenflowers.Payments` treats this as success, not failure.
  """
  use Splode.Error, fields: [:field], class: :invalid

  def message(_error), do: "already paid"
end

defmodule Edenflowers.Payments.Errors.AmountMismatch do
  @moduledoc "Returned when a course payment does not cover the booking's stored amount."
  use Splode.Error, fields: [:field, :expected, :actual], class: :invalid

  def message(error), do: "Payment amount #{error.actual} does not match #{error.expected}"
end

defmodule Edenflowers.Payments.Errors.PaymentIntentMismatch do
  @moduledoc "Returned when a PaymentIntent is not the one stored on the record it claims to pay for."
  use Splode.Error, fields: [:field, :expected, :actual], class: :invalid

  def message(error), do: "PaymentIntent #{error.actual} does not match #{error.expected}"
end

defmodule Edenflowers.Payments.Errors.UnexpectedPayment do
  @moduledoc """
  Returned when a payment link payment arrives for an order that no longer
  expects one: it was paid in person, or cancelled. Jennie has to refund it.
  """
  use Splode.Error, fields: [:field, :reason], class: :invalid

  # The reason arrives as a string when the check runs in the database.
  def message(%{reason: reason}) when reason in [:paid_in_person, "paid_in_person"],
    do: "order was already paid in person"

  def message(%{reason: reason}) when reason in [:cancelled, "cancelled"], do: "order was cancelled"
end
