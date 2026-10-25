defmodule Edenflowers.Payments.Errors.AlreadyPaid do
  @moduledoc """
  Returned when an action would record a payment for something already paid.
  Stripe delivers webhooks at least once, so `Edenflowers.Payments` treats this
  as success, not failure.
  """
  use Splode.Error, fields: [:field], class: :invalid

  def message(_error), do: "already paid"
end

defmodule Edenflowers.Payments.Errors.PaymentInProgress do
  @moduledoc "Returned when an attached payment is processing or succeeded and prevents deletion."
  use Splode.Error, fields: [:field], class: :invalid
  use GettextSigils, backend: EdenflowersWeb.Gettext

  def message(_error),
    do: ~t"A payment for this order is under way. Wait for it to arrive, then cancel the order instead."
end

defmodule Edenflowers.Payments.Errors.PaymentIntentMismatch do
  @moduledoc "Returned when a PaymentIntent is not the one stored on the record it claims to pay for."
  use Splode.Error, fields: [:field, :expected, :actual], class: :invalid

  def message(error), do: "PaymentIntent #{error.actual} does not match #{error.expected}"
end

defmodule Edenflowers.Payments.Errors.NotPayable do
  @moduledoc """
  Returned when preparing a payment for something that can't be paid now:
  `reason` says why, and `line_items` are the ones over stock.
  """
  use Splode.Error, fields: [:reason, line_items: []], class: :invalid

  def message(error), do: "not payable: #{error.reason}"

  @doc "The NotPayable among an action's errors, or nil."
  def find(%{errors: errors}), do: Enum.find(errors, &is_struct(&1, __MODULE__))
  def find(_error), do: nil
end
