defmodule EdenflowersWeb.Admin.OrderLog do
  @moduledoc """
  Turns an order's paper trail versions and payments into the log on its
  admin page, newest first.

  Payments come from their own records rather than versions: a Stripe refund
  changes nothing on the order row, and only the record holds the amount.
  Lines live on another resource, so a version shows them only through its
  `items`, which `RecordEnteredLineItems` sets when they change.
  """
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  alias Edenflowers.Format
  alias Edenflowers.Locales

  @shown_fields [
    :fulfillment_date,
    :fulfillment_option_name,
    :delivery_address,
    :delivery_instructions,
    :quoted_fulfillment_fee,
    :recipient_name,
    :recipient_phone_number,
    :card_message,
    :customer_name,
    :customer_email,
    :customer_phone_number,
    :customer_instagram,
    :locale,
    :florist_note
  ]

  # `order` gives what the versions don't record: its kind and fulfillment method.
  def entries(versions, payments, locale, order \\ %{}) do
    (Enum.map(versions, &entry(&1, locale, order)) ++ Enum.map(payments, &payment_entry(&1, locale)))
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
  end

  def payment_method_label(:stripe), do: ~t"Stripe"
  def payment_method_label(:zettle), do: ~t"Card (Zettle)"
  def payment_method_label(:mobilepay), do: ~t"MobilePay"
  def payment_method_label(:cash), do: ~t"Cash"
  def payment_method_label(:zervant), do: ~t"Bank transfer"
  def payment_method_label(:voucher), do: ~t"Gift voucher"
  def payment_method_label(_method), do: ~t"Unknown"

  defp payment_entry(payment, locale) do
    amount = Format.currency(Decimal.abs(payment.amount), locale)
    how = payment_method_label(payment.method)

    title =
      cond do
        payment.reverses_payment_id -> ~t"Undid #{amount} · #{how}"
        Decimal.negative?(payment.amount) -> ~t"Refunded #{amount} · #{how}"
        true -> ~t"Paid #{amount} · #{how}"
      end

    %{
      id: "payment-#{payment.id}",
      at: payment.paid_at,
      title: title,
      details: if(payment.note, do: [{nil, payment.note}], else: [])
    }
  end

  defp entry(version, locale, order) do
    %{
      id: "version-#{version.id}",
      at: version.version_inserted_at,
      title: title(version, order),
      warning?:
        version.version_action_name in [
          :record_fulfillment_email_failure,
          :record_receipt_email_failure,
          :record_payment_received_email_failure,
          :record_order_details_email_failure,
          :record_order_updated_email_failure,
          :record_payment_failed_email_failure,
          :place_unpaid_occurrence
        ],
      details: field_details(version, locale) ++ items_details(version) ++ message_details(version)
    }
  end

  # A Gift voucher sale's receipt and Payment received emails are the voucher itself, its receipt attached.
  defp title(%{version_action_name: action}, %{gift_voucher_sale?: true})
       when action in [:send_receipt_email, :send_payment_received_email],
       do: ~t"Gift voucher emailed"

  defp title(%{version_action_name: action}, %{gift_voucher_sale?: true})
       when action in [:record_receipt_email_failure, :record_payment_received_email_failure],
       do: ~t"Gift voucher email failed"

  # An Occurrence's receipt email is Subscription delivery charged.
  defp title(%{version_action_name: :send_receipt_email}, %{origin: :subscription}), do: ~t"Charge confirmation emailed"

  defp title(%{version_action_name: :record_receipt_email_failure}, %{origin: :subscription}),
    do: ~t"Charge confirmation failed"

  defp title(%{version_action_name: :mark_fulfilled}, %{fulfillment_method: :delivery}), do: ~t"Delivered"
  defp title(%{version_action_name: :mark_fulfilled}, %{fulfillment_method: :pickup}), do: ~t"Collected"

  # Versions from before the log recorded which delivery email went fall through to the general title.
  defp title(%{version_action_name: :send_fulfillment_email, fulfillment_email: "delivered"}, _order),
    do: ~t"Delivered email sent"

  defp title(%{version_action_name: :send_fulfillment_email, fulfillment_email: "left_at_door"}, _order),
    do: ~t"Left at the door email sent, with photo"

  defp title(version, _order), do: title(version)

  defp title(%{version_action_name: :place_custom}), do: ~t"Placed by Jennie"
  defp title(%{version_action_name: :sell_gift_voucher}), do: ~t"Sold in the shop"
  # The payment's own entry says how it was paid.
  defp title(%{version_action_name: action}) when action in [:finalize_checkout, :place_paid_by_voucher],
    do: ~t"Placed online"

  defp title(%{version_action_name: :place_unpaid_occurrence}), do: ~t"Placed, but the saved card was refused"
  defp title(%{version_action_name: :edit}), do: ~t"Edited"
  defp title(%{version_action_name: :update_florist_note}), do: ~t"Florist note changed"

  defp title(%{version_action_name: :link_pass_it_on_card} = version),
    do: ~t"Pass it on card #{code = version.pass_it_on_card} linked"

  defp title(%{version_action_name: :remove_pass_it_on_card} = version),
    do: ~t"Pass it on card #{code = version.pass_it_on_card} removed"

  defp title(%{version_action_name: :update_business_details}), do: ~t"Business details changed"
  defp title(%{version_action_name: :cancel}), do: ~t"Cancelled"
  defp title(%{version_action_name: :cancel_by_customer}), do: ~t"Cancelled by the customer"
  defp title(%{version_action_name: :mark_ready}), do: ~t"Marked ready"
  defp title(%{version_action_name: :undo_ready}), do: ~t"Returned to To make"
  defp title(%{version_action_name: :mark_fulfilled}), do: ~t"Fulfilled"
  defp title(%{version_action_name: :open_payment_link}), do: ~t"Payment link created"
  defp title(%{version_action_name: :send_order_details_email}), do: ~t"Order details emailed"
  defp title(%{version_action_name: :send_order_updated_email}), do: ~t"Updated order emailed"
  defp title(%{version_action_name: :send_payment_reminder}), do: ~t"Payment reminder emailed"
  defp title(%{version_action_name: :send_payment_failed_email}), do: ~t"Payment needed emailed"

  defp title(%{version_action_name: action}) when action in [:send_receipt_email, :email_receipt],
    do: ~t"Receipt emailed"

  defp title(%{version_action_name: :email_gift_voucher}), do: ~t"Gift voucher emailed"
  # Retired: kept so older sales' logs still read.
  defp title(%{version_action_name: :send_gift_voucher_to_recipient}), do: ~t"Gift voucher emailed to the recipient"

  defp title(%{version_action_name: :send_payment_received_email}), do: ~t"Payment received emailed"

  defp title(%{version_action_name: :send_fulfillment_email}), do: ~t"Fulfillment confirmation emailed"
  defp title(%{version_action_name: :record_fulfillment_email_failure}), do: ~t"Fulfillment confirmation failed"
  defp title(%{version_action_name: :record_receipt_email_failure}), do: ~t"Receipt failed"
  defp title(%{version_action_name: :record_payment_received_email_failure}), do: ~t"Payment received failed"
  defp title(%{version_action_name: :record_order_details_email_failure}), do: ~t"Order details failed"
  defp title(%{version_action_name: :record_order_updated_email_failure}), do: ~t"Updated order failed"
  defp title(%{version_action_name: :record_payment_failed_email_failure}), do: ~t"Payment needed failed"
  defp title(%{version_action_name: other}), do: to_string(other)

  # A creation's fields are the whole order, already on the page; its items show.
  defp field_details(%{version_action_type: :create}, _locale), do: []

  # The title already names the field, so the note stands alone.
  defp field_details(%{version_action_name: :update_florist_note} = version, locale) do
    [{nil, show(version.changes["florist_note"], :florist_note, locale)}]
  end

  defp field_details(%{version_action_name: action} = version, _locale) when action in [:cancel, :cancel_by_customer] do
    reason = version.changes["cancellation_reason"]
    emailed_to = version.changes["cancellation_emailed_to"]

    if(reason, do: [{~t"Reason", reason}], else: []) ++
      [if(emailed_to, do: {~t"Sent to", emailed_to}, else: {nil, ~t"The customer wasn't emailed."})]
  end

  defp field_details(%{version_action_name: :send_fulfillment_email} = version, _locale) do
    [{~t"Sent to", version.changes["fulfillment_emailed_to"]}]
  end

  defp field_details(%{version_action_name: action} = version, _locale)
       when action in [:email_gift_voucher, :send_gift_voucher_to_recipient] do
    if to = Map.get(version, :email_to), do: [{~t"Sent to", to}], else: []
  end

  defp field_details(version, locale) do
    for field <- @shown_fields, Map.has_key?(version.changes, to_string(field)) do
      {field_label(field), show(version.changes[to_string(field)], field, locale)}
    end
  end

  defp field_label(:fulfillment_date), do: ~t"Date"
  defp field_label(:fulfillment_option_name), do: ~t"Method"
  defp field_label(:delivery_address), do: ~t"Delivery address"
  defp field_label(:delivery_instructions), do: ~t"Delivery instructions"
  defp field_label(:quoted_fulfillment_fee), do: ~t"Fulfillment fee"
  defp field_label(:recipient_name), do: ~t"Recipient"
  defp field_label(:recipient_phone_number), do: ~t"Recipient phone"
  defp field_label(:card_message), do: ~t"Card message"
  defp field_label(:customer_name), do: ~t"Customer"
  defp field_label(:customer_email), do: ~t"Email"
  defp field_label(:customer_phone_number), do: ~t"Phone"
  defp field_label(:customer_instagram), do: ~t"Instagram"
  defp field_label(:locale), do: ~t"Language"
  defp field_label(:florist_note), do: ~t"Florist note"

  @doc "Jennie's words in the email a version sent: the subject and text she rewrote, or an older note."
  def message_details(version) do
    [
      {~t"Message", Map.get(version, :email_message)},
      {~t"Subject as sent", Map.get(version, :email_subject)},
      {~t"Email as sent", Map.get(version, :email_body)}
    ]
    |> Enum.reject(fn {_label, text} -> is_nil(text) end)
  end

  defp items_details(%{items: nil}), do: []
  # The items are stored as one "2 × Rose, 1 × Card" string; product names can
  # hold commas, so split only where the next item's quantity starts.
  defp items_details(version), do: [{~t"Items", String.split(version.items, ~r/, (?=\d+ × )/)}]

  defp show(nil, _field, _locale), do: "—"
  defp show(value, :quoted_fulfillment_fee, locale), do: Format.currency(Decimal.new(value), locale)
  defp show(value, :fulfillment_date, locale), do: Format.date(Date.from_iso8601!(value), locale)
  defp show(value, :locale, _locale), do: Locales.name(value)
  defp show(value, _field, _locale), do: value
end
