defmodule Edenflowers.Orders.Changes.NotifyShop do
  @moduledoc """
  Tells Jennie about a new order or subscription, or with `notice: :reminder`
  that an order starts within the hour: an email to the shop's inbox, and a
  push to every admin device that turned notifications on. Both are queued in
  the action's transaction, so they only go out for what really happened, and
  a failure never fails checkout.

  Without VAPID keys (staging, most dev machines) only the email is queued.
  """
  use Ash.Resource.Change

  alias Edenflowers.Orders.ShopNotice
  alias Edenflowers.Orders.Workers.EmailShop
  alias Edenflowers.Orders.Workers.PushToAdmins

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      args = ShopNotice.args({Keyword.get(opts, :notice, :new), record})
      args |> EmailShop.new() |> Oban.insert!()
      if Edenflowers.WebPush.configured?(), do: args |> PushToAdmins.new() |> Oban.insert!()
      {:ok, record}
    end)
  end
end
