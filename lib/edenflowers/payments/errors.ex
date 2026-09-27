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
