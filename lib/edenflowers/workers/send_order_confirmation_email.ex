defmodule Edenflowers.Workers.SendOrderConfirmationEmail do
  # Webhook deliveries are at-least-once. The unique key on `order_id` makes
  # repeated `enqueue/1` calls for the same order collapse to a single job.
  use Oban.Worker, unique: [keys: [:order_id], period: :infinity]

  import Edenflowers.Actors

  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Store.Order

  def enqueue(%{"order_id" => order_id} = args) do
    args
    |> __MODULE__.new()
    |> Oban.insert()
    |> case do
      {:ok, job} -> {:ok, job}
      {:error, changeset} -> {:error, {:enqueue_failed, order_id, changeset}}
    end
  end

  def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
    # Placed orders are immutable per ADR 0001: the live aggregates the
    # template used to read have all been frozen into `placed_*` columns by
    # SnapshotTotals at finalize_checkout. The worker only needs the order
    # row plus its line items.
    order_id
    |> Order.get_by_id!(actor: system_actor())
    |> Ash.load!([:line_items], actor: system_actor())
    |> Email.order_confirmation()
    |> Mailer.deliver()
  end
end
