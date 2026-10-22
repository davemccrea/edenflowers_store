defmodule Edenflowers.Orders.Workers.PushToAdmins do
  @moduledoc """
  Tells every admin device that turned notifications on what
  `Edenflowers.Orders.ShopNotice` says. Tapping it opens the order or
  subscription in the admin.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  require Logger

  alias Edenflowers.Accounts
  alias Edenflowers.Orders.ShopNotice
  alias Edenflowers.WebPush

  # ponytail: a retry resends to every device, not just the ones that failed.
  # The notification's tag makes a repeat replace the first silently, so it
  # only costs a request. Fan out one job per device if that ever matters.
  @impl true
  def perform(%Oban.Job{args: args}) do
    notice = ShopNotice.fetch!(args)

    failures =
      Accounts.list_admin_push_subscriptions!(authorize?: false)
      |> Enum.map(&deliver(&1, notice))
      |> Enum.reject(&(&1 == :ok))

    if failures == [], do: :ok, else: {:error, failures}
  end

  defp deliver(subscription, notice) do
    case WebPush.deliver(subscription, payload(notice, subscription.locale)) do
      :ok ->
        :ok

      {:error, :gone} ->
        Accounts.unsubscribe_from_push!(subscription, authorize?: false)
        :ok

      {:error, reason} ->
        Logger.warning("Push for #{inspect(ShopNotice.args(notice))} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp payload(notice, locale) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      Jason.encode!(%{
        title: ShopNotice.title(notice, locale),
        tag: ShopNotice.tag(notice),
        url: ShopNotice.path(notice)
      })
    end)
  end
end
