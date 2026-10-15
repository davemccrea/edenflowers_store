defmodule Edenflowers.Orders.Workers.PushNewOrder do
  @moduledoc """
  Sends a "new order" notification to every admin device that turned order
  notifications on. Tapping it opens the order in the admin.
  """
  use Oban.Worker, queue: :default, max_attempts: 5
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Logger

  alias Edenflowers.Accounts
  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias Edenflowers.WebPush

  @timezone "Europe/Helsinki"

  def new_for(order), do: new(%{"order_id" => order.id})

  # ponytail: a retry resends to every device, not just the ones that failed.
  # The notification's tag makes a repeat replace the first silently, so it
  # only costs a request. Fan out one job per device if that ever matters.
  def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
    order = Orders.get_order_by_id!(order_id, load: [:grand_total], authorize?: false)

    failures =
      Accounts.list_push_subscriptions!(authorize?: false)
      |> Enum.map(&deliver(&1, order))
      |> Enum.reject(&(&1 == :ok))

    if failures == [], do: :ok, else: {:error, failures}
  end

  defp deliver(subscription, order) do
    case WebPush.deliver(subscription, payload(order, subscription.locale)) do
      :ok ->
        :ok

      {:error, :gone} ->
        Accounts.unsubscribe_from_push!(subscription, authorize?: false)
        :ok

      {:error, reason} ->
        Logger.warning("Push for order #{order.id} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp payload(order, locale) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      title =
        if order.fulfillment_date == today(),
          do: ~t"Same-day order #{order.order_reference}",
          else: ~t"New order #{order.order_reference}"

      body =
        Enum.join(
          [fulfillment_method(order.fulfillment_method), Format.date(order.fulfillment_date, locale)],
          " "
        ) <> " · " <> Format.currency(order.grand_total, locale)

      Jason.encode!(%{
        title: title,
        body: body,
        tag: "order-#{order.id}",
        url: "/admin/orders/#{order.id}"
      })
    end)
  end

  defp fulfillment_method(:delivery), do: ~t"Delivery"
  defp fulfillment_method(:pickup), do: ~t"Pickup"

  defp today, do: @timezone |> DateTime.now!() |> DateTime.to_date()
end
