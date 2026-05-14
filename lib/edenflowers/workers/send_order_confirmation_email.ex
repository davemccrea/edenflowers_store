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
    order_id
    # TODO: use system_actor here or authorize?: false ?
    |> Order.get_by_id!(actor: system_actor(), authorize?: false)
    |> Ash.load!(
      [
        # Aggregates
        :items_subtotal,
        :items_tax,
        :discount,

        # Calculations
        :promotion_applied?,
        :grand_total,
        :tax,
        :fulfillment_tax,

        # Relationships
        :promotion,
        fulfillment_option: [:tax_rate],
        line_items: [:subtotal, :total]
      ],
      actor: system_actor(),
      authorize?: false
    )
    |> Email.order_confirmation()
    |> Mailer.deliver()
  end
end
