defmodule EdenflowersWeb.Admin.CourseLog do
  @moduledoc """
  Turns the paper trail versions and payments of a course's bookings into the
  log on its admin page, newest first. Every entry names its participant.

  Bookings made before they kept a paper trail have only their payments.
  """
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  alias EdenflowersWeb.Admin.OrderLog

  def entries(bookings, locale) do
    bookings
    |> Enum.flat_map(&booking_entries(&1, locale))
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
  end

  defp booking_entries(booking, locale) do
    versions =
      Enum.map(booking.paper_trail_versions, fn version ->
        %{
          id: "version-#{version.id}",
          at: version.version_inserted_at,
          title: title(version),
          details: details(version)
        }
      end)

    Enum.map(versions ++ OrderLog.entries([], booking.payments, locale), fn entry ->
      gettext_comment("%{event} is what happened, like \"Seat removed\"; %{name} is the participant it happened to.")
      %{entry | title: ~t"#{event = entry.title} · #{name = booking.name}"}
    end)
  end

  defp title(%{version_action_name: :add_manually}), do: ~t"Booked by Jennie"
  # The payment's own entry says how it was paid.
  defp title(%{version_action_name: action}) when action in [:confirm_payment, :confirm_paid_by_voucher],
    do: ~t"Booked online"

  defp title(%{version_action_name: action}) when action in [:send_confirmation_email, :email_receipt],
    do: ~t"Confirmation emailed"

  defp title(%{version_action_name: :open_payment_link}), do: ~t"Payment link created"
  defp title(%{version_action_name: :email_payment_link}), do: ~t"Payment link emailed"
  defp title(%{version_action_name: :send_payment_reminder}), do: ~t"Payment reminder emailed"
  defp title(%{version_action_name: :send_payment_received_email}), do: ~t"Payment received emailed"
  defp title(%{version_action_name: :send_reminder_email}), do: ~t"Course reminder emailed"
  defp title(%{version_action_name: :remove_seat}), do: ~t"Seat removed"
  defp title(%{version_action_name: :cancel}), do: ~t"Cancelled"
  defp title(%{version_action_name: other}), do: to_string(other)

  defp details(%{version_action_name: :cancel} = version) do
    reason = version.changes["cancellation_reason"]
    emailed_to = version.changes["cancellation_emailed_to"]

    if(reason, do: [{~t"Reason", reason}], else: []) ++
      [if(emailed_to, do: {~t"Sent to", emailed_to}, else: {nil, ~t"The customer wasn't emailed."})] ++
      OrderLog.message_details(version)
  end

  defp details(version), do: OrderLog.message_details(version)
end
