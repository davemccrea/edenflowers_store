defmodule Edenflowers.Workers.SendOrderConfirmationEmail do
  @moduledoc false

  use Oban.Worker

  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Store.Order

  def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
    order_id
    |> Order.get_for_confirmation_email!()
    |> Email.order_confirmation()
    |> Mailer.deliver()
  end
end
