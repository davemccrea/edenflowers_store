defmodule EdenflowersWeb.Hooks.PutNoticeBar do
  @moduledoc """
  LiveView mount hook that keeps `assigns.notice_bar` current: the line the bar above the storefront header shows,
  from `Edenflowers.Fulfillment.Availability.order_status/2`. Rechecks every minute so the bar moves on once today's
  order deadline passes or Jennie changes the calendar; checkout enforces the real deadline in between.
  """

  use Phoenix.Component
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "storefront"]

  alias Edenflowers.Format
  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Availability

  @refresh_interval :timer.minutes(1)

  def on_mount(:default, _params, _session, socket) do
    if Phoenix.LiveView.connected?(socket), do: schedule_refresh()

    socket =
      socket
      |> assign(:notice_bar, notice_bar())
      |> Phoenix.LiveView.attach_hook(:refresh_notice_bar, :handle_info, &handle_info/2)

    {:cont, socket}
  end

  defp handle_info(:refresh_notice_bar, socket) do
    schedule_refresh()
    {:halt, assign(socket, :notice_bar, notice_bar())}
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  defp schedule_refresh, do: Process.send_after(self(), :refresh_notice_bar, @refresh_interval)

  defp notice_bar do
    now = Edenflowers.ShopTime.now()
    locale = Format.locale()

    case Availability.order_status(Fulfillment.get_shop_calendar!(), now) do
      nil ->
        nil

      {:order_today, deadline} ->
        gettext_comment(
          "Storefront bar above the header. %{time} is today's order deadline, e.g. 14:00. Must fit one line on a 320px phone, about 45 characters."
        )

        ~t"Order by #{time = Format.time(deadline, locale)} for delivery today"

      {:next_open, date} ->
        if date == Date.add(DateTime.to_date(now), 1) do
          ~t"Next delivery or pickup is tomorrow"
        else
          gettext_comment("Storefront bar above the header. %{date} is a weekday and date, e.g. Thursday 29.10.")
          ~t"Next delivery or pickup is #{date = Format.weekday_day_month(date, locale)}"
        end
    end
  end
end
