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

  @doc """
  The cancel drawer's form for an order or a booking. `held` is what it held
  as the drawer opens, and goes back with the form, so the cancel works out
  what's kept from what Jennie saw.
  """
  def cancel_form(payable) do
    held = payable.amount_held |> Decimal.max(0) |> Decimal.to_string(:normal)

    Phoenix.Component.to_form(%{"refund" => held, "held" => held, "message" => "", "email_customer" => "true"},
      as: :cancel
    )
  end

  def cancel(payable, params, actor) do
    input = %{
      refund: params["refund"] && String.replace(params["refund"], ",", "."),
      held: params["held"],
      cancellation_reason: params["message"],
      email_customer?: params["email_customer"] != "false"
    }

    with {:error, error} <- Ash.update(payable, input, action: :cancel, actor: actor) do
      unless match?(%Ash.Error.Invalid{}, error),
        do: Logger.error("#{inspect(payable.__struct__)} #{payable.id} not cancelled: #{inspect(error)}")

      {:error, payment_error(error)}
    end
  end

  def record_payment(payable, %{"amount" => amount, "payment_method" => payment_method} = params, actor) do
    input = %{
      amount: String.replace(amount, ",", "."),
      payment_method: payment_method,
      email_receipt?: params["email_receipt"] == "true",
      message: params["message"]
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

  def refund(payable, %{"amount" => amount, "how" => how} = params, actor) do
    input = %{
      amount: String.replace(amount, ",", "."),
      payment_method: how,
      note: params["note"],
      email_customer?: params["email_customer"] != "false"
    }

    case Ash.update(payable, input, action: :refund, actor: actor) do
      {:ok, _payable} when how == "stripe" -> {:info, ~t"Refunded with Stripe."}
      {:ok, _payable} -> {:info, ~t"Refund recorded."}
      {:error, error} -> {:error, payment_error(error)}
    end
  end

  @doc """
  The refund form as Jennie changes it. Choosing cash unticks the email,
  since she hands that back in person; any other way ticks it again.
  """
  def refund_params(params, ["refund", "how"]),
    do: Map.put(params, "email_customer", if(params["how"] == "cash", do: "false", else: "true"))

  def refund_params(params, _target), do: params

  def open_payment_link(payable, actor) do
    case Ash.update(payable, %{}, action: :open_payment_link, actor: actor) do
      {:ok, _payable} ->
        {:info, ~t"Payment link created."}

      {:error, error} ->
        Logger.error("Payment link for #{inspect(payable.__struct__)} #{payable.id} not created: #{inspect(error)}")
        {:error, ~t"Could not create a payment link."}
    end
  end

  def email_payment_link(payable, message, actor) do
    case send_payment_link(payable, message, actor) do
      {:ok, _payable} ->
        {:info, ~t"Payment link emailed."}

      {:error, error} ->
        Logger.error("Payment link for #{inspect(payable.__struct__)} #{payable.id} not emailed: #{inspect(error)}")
        {:error, ~t"Could not email the payment link."}
    end
  end

  # Orders send theirs in a Payment reminder.
  defp send_payment_link(%CourseRegistration{} = registration, message, actor),
    do: Courses.email_registration_payment_link(registration, %{message: message}, actor: actor)

  @doc "Why recording money was refused, in the action's own words."
  def payment_error(%{errors: [%{message: message} | _]}) when is_binary(message), do: message
  def payment_error(_error), do: ~t"Could not record it. Check the amount."
end
