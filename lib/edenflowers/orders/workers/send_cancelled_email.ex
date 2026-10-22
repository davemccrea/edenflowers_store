defmodule Edenflowers.Orders.Workers.SendCancelledEmail do
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  def new_for(order, %{refunded: refunded, to_return: to_return}, cancelled_by) do
    new(%{
      "order_id" => order.id,
      "refunded_amount" => Decimal.to_string(refunded),
      "to_return" => Decimal.to_string(to_return),
      "cancelled_by" => to_string(cancelled_by)
    })
  end

  # Jobs queued before a cancel could leave money to return were all the customer's own.
  @impl true
  def perform(%Oban.Job{args: %{"order_id" => order_id, "refunded_amount" => refunded} = args}) do
    order =
      Edenflowers.Orders.get_order_by_id!(order_id,
        load: [:customer_first_name, :recipient_first_name, :payments],
        authorize?: false
      )

    money = %{refunded: Decimal.new(refunded), to_return: Decimal.new(Map.get(args, "to_return", "0"))}
    cancelled_by = if args["cancelled_by"] == "shop", do: :shop, else: :customer

    with {:ok, _result} <- order |> Email.order_cancelled(money, cancelled_by) |> Mailer.deliver() do
      Logger.info("Sent cancelled email for order #{order_id}")
      :ok
    end
  end
end
