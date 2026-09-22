defmodule Edenflowers.Courses.Payment do
  @moduledoc """
  Orchestrates Stripe payments for course bookings. Kept apart from
  `Edenflowers.Orders.Payment` on purpose: the two share the Stripe calls but
  nothing about what is being paid for.
  """

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Courses
  alias Edenflowers.Courses.Workers.SendCourseConfirmationEmail
  alias Edenflowers.External.StripeAPI

  def setup_payment(registration) do
    case stripe_api().create_course_payment_intent(registration) do
      {:ok, payment_intent} ->
        persist_payment_intent(registration, payment_intent)

      {:error, reason} ->
        Logger.error("Failed to create payment intent for course registration #{registration.id}: #{inspect(reason)}")
        {:error, :payment_intent_create_failed}
    end
  end

  @doc """
  Confirms the booking for a succeeded PaymentIntent and enqueues its
  confirmation email. Shared by the Stripe webhook and the reconciliation job,
  so either may run first or both may run.

  Returns `{:ok, registration}` when this call confirmed it, or
  `{:ok, :already_confirmed}`.
  """
  def complete_payment(registration_id, payment_intent) do
    with {:ok, outcome} <- confirm(registration_id, payment_intent),
         {:ok, _job} <- SendCourseConfirmationEmail.enqueue(%{"course_registration_id" => registration_id}) do
      {:ok, outcome}
    end
  end

  defp confirm(registration_id, payment_intent) do
    case Courses.get_registration_by_id(registration_id, actor: system_actor()) do
      {:ok, %{status: :confirmed}} ->
        {:ok, :already_confirmed}

      {:ok, registration} ->
        with :ok <- verify_payment_intent_id(payment_intent, registration),
             :ok <- verify_amount(payment_intent, registration) do
          confirm_registration(registration, payment_intent)
        end

      {:error, reason} ->
        {:error, {:payment_update_failed, registration_id, reason}}
    end
  end

  defp verify_payment_intent_id(%{id: pi_id}, registration) do
    if pi_id == registration.payment_intent_id do
      :ok
    else
      {:error, {:payment_intent_mismatch, registration.id, registration.payment_intent_id, pi_id}}
    end
  end

  defp verify_amount(%{amount_received: amount_received}, registration) do
    expected_cents = StripeAPI.to_stripe_amount(registration.amount)

    if amount_received == expected_cents do
      :ok
    else
      {:error, {:amount_mismatch, registration.id, expected_cents, amount_received}}
    end
  end

  defp confirm_registration(registration, payment_intent) do
    case Courses.confirm_registration_payment(registration, actor: system_actor()) do
      {:ok, registration} ->
        Logger.info(
          "Confirmed course registration #{registration.id} for PaymentIntent #{payment_intent.id} " <>
            "(#{payment_intent.amount_received} cents)"
        )

        {:ok, registration}

      {:error, reason} ->
        recover_already_confirmed(registration.id, reason)
    end
  end

  # A concurrent webhook delivery or reconciliation run may have confirmed it
  # between our read and write.
  defp recover_already_confirmed(registration_id, reason) do
    case Courses.get_registration_by_id(registration_id, actor: system_actor()) do
      {:ok, %{status: :confirmed}} -> {:ok, :already_confirmed}
      _ -> {:error, {:payment_update_failed, registration_id, reason}}
    end
  end

  defp persist_payment_intent(registration, payment_intent) do
    case Courses.add_registration_payment_intent_id(registration, payment_intent.id, actor: system_actor()) do
      {:ok, registration} ->
        Logger.info(
          "Created PaymentIntent #{payment_intent.id} for course registration #{registration.id} " <>
            "(#{payment_intent.amount} cents)"
        )

        {:ok, registration, payment_intent.client_secret}

      {:error, reason} ->
        stripe_api().cancel_payment_intent(payment_intent)

        Logger.error(
          "Failed to persist payment_intent_id for course registration #{registration.id}: #{inspect(reason)}"
        )

        {:error, :payment_intent_persist_failed}
    end
  end

  defp stripe_api, do: Application.get_env(:edenflowers, :stripe_api, Edenflowers.External.StripeAPI)
end
