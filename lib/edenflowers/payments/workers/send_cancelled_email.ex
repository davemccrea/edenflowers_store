defmodule Edenflowers.Payments.Workers.SendCancelledEmail do
  @moduledoc """
  Oban job that tells the customer an order or course booking was cancelled and what money remains to return:
  Cancellation confirmed when they cancelled it themselves, else the shop's cancellation.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Payments

  def new_for(record, %{refunded: refunded, to_return: to_return}, cancelled_by) do
    new(%{
      (Payments.parent_key(record) |> to_string()) => record.id,
      "refunded_amount" => Decimal.to_string(refunded),
      "to_return" => Decimal.to_string(to_return),
      "cancelled_by" => to_string(cancelled_by)
    })
  end

  @impl true
  def perform(%Oban.Job{args: args}) do
    money = %{refunded: Decimal.new(args["refunded_amount"]), to_return: Decimal.new(args["to_return"])}

    record = Payments.get_for_customer_email!(args)

    # Only an Online Order's customer cancels it themselves.
    email =
      case args["cancelled_by"] do
        "customer" -> Email.cancellation_confirmed(record, money)
        "shop" -> Email.cancelled(record, money)
      end

    with {:ok, _result} <- Mailer.deliver(email) do
      Logger.info("Sent cancelled email for #{inspect(args)}")
      :ok
    end
  end
end
