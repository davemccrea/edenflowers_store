defmodule Edenflowers.Orders.Workers.EmailShop do
  @moduledoc """
  Emails the shop's inbox what `Edenflowers.Orders.ShopNotice` says, with a
  link to it in the admin. Unlike the push, it doesn't depend on a device staying
  subscribed.
  """
  # After the customer's own email (AshOban jobs run at 2), so tests draining
  # the queue see that one first.
  use Oban.Worker, queue: :default, max_attempts: 5, priority: 3

  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Orders.ShopNotice

  @impl true
  def perform(%Oban.Job{args: args}) do
    with {:ok, _result} <- args |> ShopNotice.fetch!() |> Email.shop_notice() |> Mailer.deliver(), do: :ok
  end
end
