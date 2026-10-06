defmodule EdenflowersWeb.Admin.OrderLog do
  @moduledoc """
  Turns an order's paper trail versions into the log on its admin page,
  newest first.

  Payments aren't in the log: the order page lists them from their own records.
  Lines live on another resource, so a version shows them only through its
  `items`, which `ReplaceLineItems` sets when they change.
  """
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Format
  alias Edenflowers.Locales

  @shown_fields [
    :fulfillment_date,
    :fulfillment_option_name,
    :delivery_address,
    :delivery_instructions,
    :fulfillment_fee,
    :recipient_name,
    :recipient_phone_number,
    :card_message,
    :customer_name,
    :customer_email,
    :customer_phone_number,
    :locale,
    :florist_note
  ]

  def entries(versions, locale) do
    versions
    |> Enum.sort_by(& &1.version_inserted_at, {:desc, DateTime})
    |> Enum.map(&entry(&1, locale))
  end

  defp entry(version, locale) do
    %{
      at: version.version_inserted_at,
      title: title(version),
      details: field_details(version, locale) ++ items_details(version)
    }
  end

  defp title(%{version_action_name: action}) do
    case action do
      :place_custom -> ~t"Placed by Jennie"
      :finalize_checkout -> ~t"Placed and paid online"
      :edit -> ~t"Edited"
      :update_florist_note -> ~t"Florist note changed"
      :cancel -> ~t"Cancelled"
      :mark_fulfilled -> ~t"Fulfilled"
      :open_payment_link -> ~t"Payment link created"
      :send_order_details_email -> ~t"Order details emailed"
      :send_confirmation_email -> ~t"Receipt emailed"
      :email_receipt -> ~t"Receipt emailed"
      :send_delivered_email -> ~t"Delivery email sent"
      other -> to_string(other)
    end
  end

  # A creation's fields are the whole order, already on the page; its items show.
  defp field_details(%{version_action_type: :create}, _locale), do: []

  # The title already names the field, so the note stands alone.
  defp field_details(%{version_action_name: :update_florist_note} = version, locale) do
    [{nil, show(version.changes["florist_note"], :florist_note, locale)}]
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
  defp field_label(:fulfillment_fee), do: ~t"Fulfillment fee"
  defp field_label(:recipient_name), do: ~t"Recipient"
  defp field_label(:recipient_phone_number), do: ~t"Recipient phone"
  defp field_label(:card_message), do: ~t"Card message"
  defp field_label(:customer_name), do: ~t"Customer"
  defp field_label(:customer_email), do: ~t"Email"
  defp field_label(:customer_phone_number), do: ~t"Phone"
  defp field_label(:locale), do: ~t"Language"
  defp field_label(:florist_note), do: ~t"Florist note"

  defp items_details(%{items: nil}), do: []
  # The items are stored as one "2 × Rose, 1 × Card" string; product names can
  # hold commas, so split only where the next item's quantity starts.
  defp items_details(version), do: [{~t"Items", String.split(version.items, ~r/, (?=\d+ × )/)}]

  defp show(nil, _field, _locale), do: "—"
  defp show(value, :fulfillment_fee, locale), do: Format.currency(Decimal.new(value), locale)
  defp show(value, :fulfillment_date, locale), do: Format.date(Date.from_iso8601!(value), locale)
  defp show(value, :locale, _locale), do: Locales.name(value)
  defp show(value, _field, _locale), do: value
end
