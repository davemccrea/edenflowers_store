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

  # The Order is already a snapshot — totals and line items are flat
  # attributes/relationships, not derived from a related Cart. So all the
  # email needs is the line_items relation and the promotion (for the code
  # display).
  def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
    order_id
    |> Order.get_for_confirmation!(actor: system_actor(), authorize?: false)
    |> Email.order_confirmation()
    |> Mailer.deliver()
  end
end
