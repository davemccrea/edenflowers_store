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

  # All numeric values are now flat `placed_*` attributes on the order
  # (snapshotted at finalize_checkout) and per-line-item `placed_*` columns.
  # No live aggregates or calculations are loaded — a later edit to a tax
  # rate, a promotion percentage, or a fulfillment option's pricing must
  # not change what the customer's confirmation email says.
  def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
    order_id
    |> Order.get_by_id!(actor: system_actor(), authorize?: false)
    |> Ash.load!([:line_items], actor: system_actor(), authorize?: false)
    |> Email.order_confirmation()
    |> Mailer.deliver()
  end
end
