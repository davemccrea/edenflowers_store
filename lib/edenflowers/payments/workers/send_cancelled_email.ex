defmodule Edenflowers.Payments.Workers.SendCancelledEmail do
  @moduledoc """
  Oban job that tells the customer an order or course booking was cancelled and what money remains to return or collect:
  Cancellation confirmed when they cancelled it themselves, else the shop's cancellation.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Email.Edits
  alias Edenflowers.Mailer
  alias Edenflowers.Payments

  def new_for(record, money, cancelled_by, edits) do
    new(%{
      (Payments.parent_key(record) |> to_string()) => record.id,
      "charge" => Decimal.to_string(money.charge),
      "refunded_amount" => Decimal.to_string(money.refunded),
      "back_on_voucher" => Decimal.to_string(money.back_on_voucher),
      "to_return" => Decimal.to_string(money.to_return),
      "to_collect" => Decimal.to_string(money.to_collect),
      "cancelled_by" => to_string(cancelled_by),
      "subject" => edits[:subject],
      "body" => edits[:body]
    })
  end

  @impl true
  def perform(%Oban.Job{args: args}) do
    # Older queued jobs lack charge and to_collect, or back_on_voucher if they
    # predate vouchers. Default those missing amounts to zero so they can still run.
    money = %{
      charge: Decimal.new(args["charge"] || "0"),
      refunded: Decimal.new(args["refunded_amount"]),
      back_on_voucher: Decimal.new(args["back_on_voucher"] || "0"),
      to_return: Decimal.new(args["to_return"]),
      to_collect: Decimal.new(args["to_collect"] || "0")
    }

    record = Payments.get_for_customer_email!(args)

    # Only an Online Order's customer cancels it themselves.
    email =
      case args["cancelled_by"] do
        "customer" -> Email.cancellation_confirmed(record, money)
        "shop" -> Email.cancelled(record, money)
      end

    with {:ok, _result} <- email |> Edits.apply_to(%{subject: args["subject"], body: args["body"]}) |> Mailer.deliver() do
      Logger.info("Sent cancelled email for #{inspect(Map.drop(args, ["subject", "body"]))}")
      :ok
    end
  end
end
