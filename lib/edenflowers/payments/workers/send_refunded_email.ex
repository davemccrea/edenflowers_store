defmodule Edenflowers.Payments.Workers.SendRefundedEmail do
  @moduledoc """
  Oban job that tells the customer about a completed refund.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Email.Edits
  alias Edenflowers.Mailer
  alias Edenflowers.Payments

  def new_for(record, %{amount: amount, payment_method: method} = arguments) do
    new(%{
      (Payments.parent_key(record) |> to_string()) => record.id,
      "amount" => Decimal.to_string(amount),
      "payment_method" => to_string(method),
      "subject" => arguments[:subject],
      "body" => arguments[:body]
    })
  end

  @impl true
  def perform(%Oban.Job{args: args}) do
    refund = %{
      amount: Decimal.new(args["amount"]),
      payment_method: String.to_existing_atom(args["payment_method"])
    }

    with {:ok, _result} <-
           args
           |> Payments.get_for_customer_email!()
           |> Email.refunded(refund)
           |> Edits.apply_to(%{subject: args["subject"], body: args["body"]})
           |> Mailer.deliver() do
      Logger.info("Sent refunded email for #{inspect(Map.drop(args, ["subject", "body"]))}")
      :ok
    end
  end
end
