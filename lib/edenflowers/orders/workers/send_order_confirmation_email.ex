defmodule Edenflowers.Orders.Workers.SendOrderConfirmationEmail do
  # Webhook deliveries are at-least-once. The unique key on `order_id` makes
  # repeated `enqueue/1` calls for the same order collapse to a single job.
  use Oban.Worker, unique: [keys: [:order_id], period: :infinity]

  import Edenflowers.Actors

  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Orders.Receipt
  alias Edenflowers.Orders.Order

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
    order =
      order_id
      |> Order.get_by_id!(actor: system_actor(), authorize?: false)
      |> load_for_send()

    # Skip if a prior Oban attempt already delivered + marked.
    if order.receipt_emailed_at do
      :ok
    else
      send_with_receipt(order)
    end
  end

  defp send_with_receipt(order) do
    with {:ok, pdf} <- Receipt.generate(order),
         sha = sha256_hex(pdf),
         email = build_email(order, pdf),
         {:ok, _result} <- Mailer.deliver(email),
         {:ok, _order} <-
           Order.mark_receipt_emailed(order, sha, actor: system_actor()) do
      :ok
    end
  end

  defp build_email(order, pdf) do
    attachment =
      Swoosh.Attachment.new(
        {:data, pdf},
        filename: "eden-flowers-#{order.order_reference}.pdf",
        content_type: "application/pdf"
      )

    order
    |> Email.order_confirmation()
    |> Swoosh.Email.attachment(attachment)
  end

  defp sha256_hex(bytes) do
    :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  end

  defp load_for_send(order) do
    Ash.load!(
      order,
      [
        :customer_first_name,
        :items_subtotal,
        :items_tax,
        :discount,
        :promotion_applied?,
        :grand_total,
        :tax,
        :fulfillment_tax,
        line_items: [:subtotal, :total, :unit_price_ex_tax]
      ],
      actor: system_actor(),
      authorize?: false
    )
  end
end
