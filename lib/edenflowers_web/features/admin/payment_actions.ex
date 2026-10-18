defmodule EdenflowersWeb.Admin.PaymentActions do
  @moduledoc """
  Jennie's payment controls on an order or a course booking, shared by the
  order page and the courses page. Each returns the flash to show, and the
  page reloads what it shows.
  """
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Logger

  alias Edenflowers.Courses
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Orders
  alias Edenflowers.Payments

  def record_payment(payable, %{"amount" => amount, "payment_method" => payment_method}, actor) do
    amount = String.replace(amount, ",", ".")

    case Ash.update(payable, %{amount: amount, payment_method: payment_method}, action: :record_payment, actor: actor) do
      {:ok, _payable} -> {:info, ~t"Payment recorded."}
      {:error, error} -> {:error, payment_error(error)}
    end
  end

  def undo_payment(payable, payment_id, actor) do
    case Ash.update(payable, %{payment_id: payment_id}, action: :undo_payment, actor: actor) do
      {:ok, _payable} -> {:info, ~t"Payment undone."}
      {:error, _error} -> {:error, ~t"Could not undo the payment."}
    end
  end

  def refund_with_stripe(payable) do
    case Payments.refund_balance(payable) do
      {:ok, refunds} ->
        {:info, refund_message(refunds)}

      {:error, reason} ->
        Logger.error("Stripe refund for #{inspect(payable.__struct__)} #{payable.id} failed: #{inspect(reason)}")
        {:error, ~t"Could not refund with Stripe. Check the payment in Stripe."}
    end
  end

  def open_payment_link(payable, actor) do
    case Ash.update(payable, %{}, action: :open_payment_link, actor: actor) do
      {:ok, _payable} -> {:info, ~t"Payment link created."}
      {:error, _error} -> {:error, ~t"Could not create a payment link."}
    end
  end

  def email_payment_link(payable, actor) do
    case send_payment_link(payable, actor) do
      {:ok, _payable} -> {:info, ~t"Payment link emailed."}
      {:error, _error} -> {:error, ~t"Could not email the payment link."}
    end
  end

  defp send_payment_link(%CourseRegistration{} = registration, actor),
    do: Courses.email_registration_payment_link(registration, actor: actor)

  # The order details email carries the link, so sending it is opening one.
  defp send_payment_link(order, actor) do
    with {:ok, order} <- Orders.open_payment_link(order, actor: actor) do
      Orders.send_order_details_email(order, actor: actor)
    end
  end

  # Why recording money was refused, in the action's own words.
  defp payment_error(%{errors: [%{message: message} | _]}) when is_binary(message), do: message
  defp payment_error(_error), do: ~t"Could not record it. Check the amount."

  defp refund_message([]), do: ~t"Nothing left to refund. Stripe already has refunds covering it."

  defp refund_message(refunds) do
    if Enum.all?(refunds, &(&1.status == "succeeded")),
      do: ~t"Refunded with Stripe.",
      else: ~t"Refund sent to Stripe. It shows here once it goes through."
  end
end
