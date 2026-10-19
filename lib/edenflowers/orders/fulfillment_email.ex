defmodule Edenflowers.Orders.FulfillmentEmail do
  import Ecto.Query

  alias Edenflowers.Repo

  @worker "Edenflowers.Orders.Workers.SendDeliveredEmail"

  def status(order) do
    status =
      cond do
        order.delivered_emailed_at -> %{state: :sent, sent_at: order.delivered_emailed_at}
        order.fulfillment_status != :fulfilled or order.state != :placed -> %{state: :not_fulfilled}
        is_nil(order.customer_email) -> %{state: :no_email}
        order.skip_delivered_email -> %{state: :skipped}
        true -> job_status(latest_job(order.id))
      end

    Map.merge(%{retry?: false, poll?: false, reason: nil, sent_at: nil}, status)
  end

  def retry(order, actor) do
    order.id
    |> jobs()
    |> where([job], job.state == "retryable")
    |> Oban.retry_all_jobs()

    AshOban.run_trigger(order, :send_delivered_email, actor: actor)
    :ok
  end

  defp latest_job(order_id) do
    order_id |> jobs() |> order_by([job], desc: job.id) |> limit(1) |> Repo.one()
  end

  defp jobs(order_id) do
    from job in Oban.Job,
      where: job.worker == @worker and fragment("?->'primary_key'->>'id' = ?", job.args, ^order_id)
  end

  defp job_status(nil), do: %{state: :pending, retry?: true, poll?: true}
  defp job_status(%{state: "executing"}), do: %{state: :sending, poll?: true}

  defp job_status(%{state: state}) when state in ["available", "scheduled"],
    do: %{state: :queued, poll?: true}

  defp job_status(%{state: state, errors: errors}) when state in ["retryable", "discarded", "cancelled"] do
    error = errors |> List.last() |> Kernel.||(%{}) |> Map.get("error", "")

    reason =
      if error =~ ~r/delivery_photo_slug|imgproxy|Delivery photo is missing/, do: :photo_unavailable, else: :send_failed

    %{
      state: if(state == "retryable", do: :retrying, else: :failed),
      retry?: true,
      poll?: state == "retryable",
      reason: reason
    }
  end

  defp job_status(_job), do: %{state: :pending, retry?: true, poll?: true}
end
