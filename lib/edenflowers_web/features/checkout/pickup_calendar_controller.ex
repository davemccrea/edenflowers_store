defmodule EdenflowersWeb.Checkout.PickupCalendarController do
  use EdenflowersWeb, :controller

  alias EdenflowersWeb.Checkout.OrderLive

  def show(conn, %{"id" => id}) do
    case OrderLive.get_order(id, get_session(conn, :guest_order_id), conn.assigns[:current_user]) do
      {:ok, %{state: :placed, fulfillment_method: :pickup} = order} ->
        send_download(conn, {:binary, ics(order)},
          filename: "eden-flowers-pickup.ics",
          content_type: "text/calendar"
        )

      _ ->
        send_resp(conn, :not_found, "Not found")
    end
  end

  # An all-day event: pickup has no time slot, only a date.
  def ics(order) do
    date = order.fulfillment_date

    [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//Eden Flowers//Pickup//EN",
      "BEGIN:VEVENT",
      "UID:pickup-#{order.id}@edenflowers.fi",
      "DTSTAMP:#{Calendar.strftime(DateTime.utc_now(), "%Y%m%dT%H%M%SZ")}",
      "DTSTART;VALUE=DATE:#{Calendar.strftime(date, "%Y%m%d")}",
      "DTEND;VALUE=DATE:#{Calendar.strftime(Date.add(date, 1), "%Y%m%d")}",
      "SUMMARY:#{escape(~t"Pick up your flowers from Eden Flowers")}",
      "LOCATION:#{escape(Edenflowers.Fulfillment.shop_address())}",
      "DESCRIPTION:#{escape(~t"Order #{order.order_reference}")}",
      "END:VEVENT",
      "END:VCALENDAR"
    ]
    |> Enum.map_join(&(&1 <> "\r\n"))
  end

  defp escape(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace(",", "\\,")
    |> String.replace(";", "\\;")
    |> String.replace("\n", "\\n")
  end
end
