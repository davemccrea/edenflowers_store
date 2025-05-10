defmodule Edenflowers.Workers.SendOrderConfirmationEmail do
  use Oban.Worker

  import Swoosh.Email

  alias Edenflowers.Mailer
  alias Edenflowers.Store.Order

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
    order = Order.get_by_id!(order_id)

    new()
    |> to({order.customer_name, order.customer_email})
    |> from({"Jennie", "info@edenflowers.fi"})
    |> subject("Thank you for your order")
    |> text_body("Testing testing")
    |> Mailer.deliver()
  end
end
