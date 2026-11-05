defmodule EdenflowersWeb.Admin.PaymentActions do
  @moduledoc """
  Jennie's payment controls on an order or a course booking, shared by the
  order page and the courses page. Returns the flash to show, keeping a
  committed payment distinct from a receipt failure. The page reloads what it shows.
  """
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  require Logger

  alias Edenflowers.Courses
  alias Edenflowers.Courses.CourseRegistration
  alias EdenflowersWeb.Admin.Drawers

  @doc """
  The cancel drawer's form for an order or a booking. The cancellation charge
  starts at `default_cancellation_charge`. `held` and `total` only tell
  Jennie what was paid and what it cost, so they go back with the form for
  the drawer to show again, but not to the action.
  """
  def cancel_form(payable) do
    payable = Ash.load!(payable, [:amount_held, :total_due, :default_cancellation_charge], authorize?: false)

    Phoenix.Component.to_form(
      %{
        "charge" => Decimal.to_string(payable.default_cancellation_charge, :normal),
        "held" => Decimal.to_string(Decimal.max(payable.amount_held, 0), :normal),
        "total" => Decimal.to_string(Decimal.max(payable.total_due, 0), :normal),
        "reason" => "",
        "email_customer" => "true"
      },
      as: :cancel
    )
  end

  def cancel(payable, params, actor) do
    input =
      Map.merge(Drawers.email_edits(params), %{
        cancellation_charge: params["charge"],
        cancellation_reason: params["reason"],
        email_customer?: params["email_customer"] != "false"
      })

    with {:error, error} <- Ash.update(payable, input, action: :cancel, actor: actor) do
      unless match?(%Ash.Error.Invalid{}, error),
        do: Logger.error("#{inspect(payable.__struct__)} #{payable.id} not cancelled: #{inspect(error)}")

      {:error, payment_error(error)}
    end
  end

  def record_payment(payable, %{"payment_method" => "voucher"} = params, actor) do
    case Ash.update(payable, %{code: params["code"]}, action: :pay_with_gift_voucher, actor: actor) do
      {:ok, _payable} -> {:success, ~t"Paid from the gift voucher."}
      {:error, error} -> {:error, payment_error(error)}
    end
  end

  def record_payment(payable, %{"amount" => amount, "payment_method" => payment_method} = params, actor) do
    input =
      Map.merge(Drawers.email_edits(params), %{
        amount: amount,
        payment_method: payment_method,
        email_receipt?: params["email_receipt"] == "true"
      })

    case Ash.update(payable, input, action: :record_payment, actor: actor) do
      {:ok, payable} -> {:ok, recorded_message(payable.__metadata__[:receipt_emailed?])}
      {:error, error} -> {:error, payment_error(error)}
    end
  end

  defp recorded_message(true), do: {:success, ~t"Payment recorded and receipt emailed."}
  defp recorded_message(false), do: {:error, ~t"Payment recorded, but the receipt could not be emailed."}
  defp recorded_message(nil), do: {:success, ~t"Payment recorded."}

  def undo_payment(payable, payment_id, actor) do
    payable
    |> Ash.update(%{payment_id: payment_id}, action: :undo_payment, actor: actor)
    |> logged(payable, "Undoing payment #{payment_id}", ~t"Payment undone.", ~t"Could not undo the payment.")
  end

  def refund(payable, %{"amount" => amount, "how" => how} = params, actor) do
    input =
      Map.merge(Drawers.email_edits(params), %{
        amount: amount,
        payment_method: how,
        note: params["note"],
        email_customer?: params["email_customer"] != "false"
      })

    case Ash.update(payable, input, action: :refund, actor: actor) do
      {:ok, _payable} when how == "stripe" -> {:success, ~t"Refunded with Stripe."}
      {:ok, _payable} -> {:success, ~t"Refund recorded."}
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

  @doc """
  The record payment form as Jennie changes it. Choosing a bank transfer ticks
  the receipt email, since the customer paid from home and would otherwise
  hear nothing; any other method unticks it, as she was there in person.
  """
  def payment_params(params, ["payment", "payment_method"]),
    do: Map.put(params, "email_receipt", to_string(params["payment_method"] == "zervant"))

  def payment_params(params, _target), do: params

  def open_payment_link(payable, actor) do
    payable
    |> Ash.update(%{}, action: :open_payment_link, actor: actor)
    |> logged(payable, "Creating a payment link", ~t"Payment link created.", ~t"Could not create a payment link.")
  end

  def email_payment_link(payable, edits, actor) do
    payable
    |> send_payment_link(edits, actor)
    |> logged(payable, "Emailing a payment link", ~t"Payment link emailed.", ~t"Could not email the payment link.")
  end

  defp logged({:ok, _payable}, _payable_before, _what, success, _failure), do: {:success, success}

  defp logged({:error, error}, payable, what, _success, failure) do
    Logger.error("#{what} for #{inspect(payable.__struct__)} #{payable.id} failed: #{inspect(error)}")
    {:error, failure}
  end

  # Orders send theirs in a Payment reminder.
  defp send_payment_link(%CourseRegistration{} = registration, edits, actor),
    do: Courses.email_registration_payment_link(registration, edits, actor: actor)

  @doc "Why recording money was refused, in the action's own words."
  def payment_error(%{errors: [%{message: message} | _]}) when is_binary(message), do: message
  def payment_error(_error), do: ~t"Could not record it. Check the amount."
end
