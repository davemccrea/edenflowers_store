defmodule Edenflowers.Orders.Workers.SendCancelledEmail do
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  def new_for(order, refunded_amount) do
    new(%{"order_id" => order.id, "refunded_amount" => Decimal.to_string(refunded_amount)})
  end

  @impl true
  def perform(%Oban.Job{args: %{"order_id" => order_id, "refunded_amount" => refunded_amount}}) do
    order =
      Edenflowers.Orders.get_order_by_id!(order_id,
        load: [:customer_first_name, :recipient_first_name, :payments],
        authorize?: false
      )

    with {:ok, _result} <- order |> Email.order_cancelled(Decimal.new(refunded_amount)) |> Mailer.deliver() do
      Logger.info("Sent cancelled email for order #{order_id}")
      :ok
    end
  end
end
