defmodule Edenflowers.Workers.SendOrderConfirmationEmail do
  @moduledoc false

  use Oban.Worker

  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Store.Order

  def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
    order = Order.get_for_checkout!(order_id)

    order
    |> Email.order_confirmation()
    |> Mailer.deliver()
  end
end
