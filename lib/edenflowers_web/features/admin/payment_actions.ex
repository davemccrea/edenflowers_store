defmodule EdenflowersWeb.Admin.PaymentActions do
  @moduledoc """
  Jennie's payment controls on an order or a course booking, shared by the
  order page and the courses page: the AshPhoenix forms behind the cancel,
  record payment and refund drawers, and the flash for what each did, keeping
  a committed payment distinct from a receipt failure. The page reloads what
  it shows.
  """
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  require Logger

  alias Edenflowers.Courses
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Payments.Changes.Cancel
  alias EdenflowersWeb.Admin.Drawers

  @doc "Loads what the cancel drawer shows about the money (`Changes.Cancel.load/0`)."
  def load_for_cancel(payable), do: Ash.load!(payable, Cancel.load(), authorize?: false)

  @doc """
  The cancel drawer's form on the payable's `cancel` action, for a payable
  from `load_for_cancel/1`. The cancellation charge starts at
  `default_cancellation_charge`.
  """
  def cancel_form(payable, actor) do
    form(payable, :cancel, "cancel", actor, %{
      "cancellation_charge" => Decimal.to_string(payable.default_cancellation_charge, :normal),
      "email_customer?" => "true"
    })
  end

  @doc """
  The record payment form, on `record_payment`, or on `pay_with_gift_voucher`
  once Jennie picks Gift voucher. Starts at a card payment in the shop for the
  whole balance, without a receipt.
  """
  def payment_form(payable, actor, params \\ %{}) do
    params =
      Map.merge(
        %{
          "payment_method" => "zettle",
          "amount" => Decimal.to_string(payable.balance, :normal),
          "email_receipt?" => "false"
        },
        params
      )

    action = if params["payment_method"] == "voucher", do: :pay_with_gift_voucher, else: :record_payment
    form(payable, action, "payment", actor, params)
  end

  @doc """
  The record payment form as Jennie changes it. Choosing a bank transfer ticks
  the receipt email, since the customer paid from home and would otherwise
  hear nothing; any other method unticks it, as she was there in person.
  Choosing or leaving Gift voucher swaps the form's action.
  """
  def change_payment_form(form, params, ["payment", "payment_method"], actor),
    do:
      payment_form(
        form.source.data,
        actor,
        Map.put(params, "email_receipt?", to_string(params["payment_method"] == "zervant"))
      )

  def change_payment_form(form, params, _target, _actor), do: AshPhoenix.Form.validate(form, params)

  @doc """
  The refund form on the `refund` action: what's owed back, if anything, the
  way the record was paid, and an email to the customer.
  """
  def refund_form(record, actor) do
    owed_back = Decimal.max(Decimal.negate(record.balance), 0)

    form(record, :refund, "refund", actor, %{
      "payment_method" => to_string(record.default_refund_method),
      "amount" => if(Decimal.positive?(owed_back), do: Decimal.to_string(owed_back, :normal), else: ""),
      "email_customer?" => "true"
    })
  end

  @doc """
  The refund form as Jennie changes it. Choosing cash unticks the email,
  since she hands that back in person; any other way ticks it again.
  """
  def change_refund_form(form, params, ["refund", "payment_method"]),
    do:
      AshPhoenix.Form.validate(form, Map.put(params, "email_customer?", to_string(params["payment_method"] != "cash")))

  def change_refund_form(form, params, _target), do: AshPhoenix.Form.validate(form, params)

  @doc """
  Submits a record payment or refund form: `{:ok, {kind, flash}}` once the
  money is recorded, or `{:error, form}` with the refusal on its fields.
  """
  def submit(form, params) do
    with {:ok, payable} <- AshPhoenix.Form.submit(form, params: params) do
      {:ok, recorded(form.source.action, payable, params)}
    end
  end

  defp recorded(:pay_with_gift_voucher, _payable, _params), do: {:success, ~t"Paid from the gift voucher."}
  defp recorded(:refund, _payable, %{"payment_method" => "stripe"}), do: {:success, ~t"Refunded with Stripe."}
  defp recorded(:refund, _payable, _params), do: {:success, ~t"Refund recorded."}

  defp recorded(:record_payment, payable, _params) do
    case payable.__metadata__[:receipt_emailed?] do
      true -> {:success, ~t"Payment recorded and receipt emailed."}
      false -> {:error, ~t"Payment recorded, but the receipt could not be emailed."}
      nil -> {:success, ~t"Payment recorded."}
    end
  end

  defp form(record, action, as, actor, params) do
    record
    |> AshPhoenix.Form.for_update(action,
      as: as,
      actor: actor,
      params: params,
      transform_params: &Drawers.keep_email_edits/3
    )
    |> Phoenix.Component.to_form()
  end

  def undo_payment(payable, payment_id, actor) do
    payable
    |> Ash.update(%{payment_id: payment_id}, action: :undo_payment, actor: actor)
    |> logged(payable, "Undoing payment #{payment_id}", ~t"Payment undone.", ~t"Could not undo the payment.")
  end

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
end
