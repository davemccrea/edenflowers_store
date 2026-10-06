defmodule Edenflowers.Payments.Validations.PaymentStillExpected do
  @moduledoc """
  Fails with `UnexpectedPayment` when an online payment arrives for an order
  already paid in person, or cancelled. Checked before `NotAlreadyPaid`, which
  would otherwise pass the first case off as a harmless webhook redelivery.
  """
  use Ash.Resource.Validation

  alias Edenflowers.Payments.Errors.UnexpectedPayment

  @impl true
  def atomic(_changeset, _opts, _context) do
    [
      {:atomic, :*, expr(payment_status == :paid and payment_method != :stripe),
       expr(error(^UnexpectedPayment, %{reason: :paid_in_person}))},
      {:atomic, :*, expr(fulfillment_status == :cancelled), expr(error(^UnexpectedPayment, %{reason: :cancelled}))}
    ]
  end
end
