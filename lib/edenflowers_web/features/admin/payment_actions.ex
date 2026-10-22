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

  @doc """
  What to keep on cancelling, from the refund Jennie typed and what was held
  when she opened the drawer. `:error` for anything outside 0 to `held`.
  """
  def kept_amount(held, nil), do: {:ok, held}

  def kept_amount(held, refund) do
    case refund |> String.trim() |> String.replace(",", ".") |> Decimal.parse() do
      {refund, ""} ->
        if Decimal.negative?(refund) or Decimal.gt?(refund, held), do: :error, else: {:ok, Decimal.sub(held, refund)}

      _invalid ->
        :error
    end
  end

  def record_payment(payable, %{"amount" => amount, "payment_method" => payment_method} = params, actor) do
    input = %{
      amount: String.replace(amount, ",", "."),
      payment_method: payment_method,
      email_receipt?: params["email_receipt"] == "true"
    }

    case Ash.update(payable, input, action: :record_payment, actor: actor) do
      {:ok, payable} -> recorded_message(payable.__metadata__[:receipt_emailed?])
      {:error, error} -> {:error, payment_error(error)}
    end
  end

  defp recorded_message(true), do: {:info, ~t"Payment recorded and receipt emailed."}
  defp recorded_message(false), do: {:error, ~t"Payment recorded, but the receipt could not be emailed."}
  defp recorded_message(nil), do: {:info, ~t"Payment recorded."}

  def undo_payment(payable, payment_id, actor) do
    case Ash.update(payable, %{payment_id: payment_id}, action: :undo_payment, actor: actor) do
      {:ok, _payable} ->
        {:info, ~t"Payment undone."}

      {:error, error} ->
        Logger.error(
          "Payment #{payment_id} on #{inspect(payable.__struct__)} #{payable.id} not undone: #{inspect(error)}"
        )

        {:error, ~t"Could not undo the payment."}
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

  def goodwill_refund(payable, %{"amount" => amount, "how" => how} = params, actor) do
    amount = String.replace(amount, ",", ".")
    note = params |> Map.get("note", "") |> String.trim() |> then(&if(&1 == "", do: nil, else: &1))

    if how == "stripe",
      do: goodwill_refund_with_stripe(payable, amount, note),
      else: goodwill_refund_recorded(payable, %{amount: amount, payment_method: how, note: note}, actor)
  end

  defp goodwill_refund_with_stripe(payable, amount, note) do
    with {amount, ""} <- Decimal.parse(amount),
         true <- Decimal.positive?(amount) do
      case Payments.refund_goodwill(payable, amount, note) do
        {:ok, refunds} ->
          {:info, refund_message(refunds)}

        {:error, message} when is_binary(message) ->
          {:error, message}

        {:error, reason} ->
          Logger.error("Goodwill refund for #{inspect(payable.__struct__)} #{payable.id} failed: #{inspect(reason)}")
          {:error, ~t"Could not refund with Stripe. Check the payment in Stripe."}
      end
    else
      _invalid -> {:error, payment_error(nil)}
    end
  end

  defp goodwill_refund_recorded(payable, input, actor) do
    case Ash.update(payable, input, action: :goodwill_refund, actor: actor) do
      {:ok, _payable} -> {:info, ~t"Refund recorded."}
      {:error, error} -> {:error, payment_error(error)}
    end
  end

  def open_payment_link(payable, actor) do
    case Ash.update(payable, %{}, action: :open_payment_link, actor: actor) do
      {:ok, _payable} ->
        {:info, ~t"Payment link created."}

      {:error, error} ->
        Logger.error("Payment link for #{inspect(payable.__struct__)} #{payable.id} not created: #{inspect(error)}")
        {:error, ~t"Could not create a payment link."}
    end
  end

  def email_payment_link(payable, actor) do
    case send_payment_link(payable, actor) do
      {:ok, _payable} ->
        {:info, ~t"Payment link emailed."}

      {:error, error} ->
        Logger.error("Payment link for #{inspect(payable.__struct__)} #{payable.id} not emailed: #{inspect(error)}")
        {:error, ~t"Could not email the payment link."}
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

  @doc "Why recording money was refused, in the action's own words."
  def payment_error(%{errors: [%{message: message} | _]}) when is_binary(message), do: message
  def payment_error(_error), do: ~t"Could not record it. Check the amount."

  defp refund_message([]), do: ~t"Nothing left to refund. Stripe already has refunds covering it."

  defp refund_message(refunds) do
    if Enum.all?(refunds, &(&1.status == "succeeded")),
      do: ~t"Refunded with Stripe.",
      else: ~t"Refund sent to Stripe. It shows here once it goes through."
  end
end
