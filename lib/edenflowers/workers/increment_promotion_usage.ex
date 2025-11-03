defmodule Edenflowers.Workers.IncrementPromotionUsage do
  use Oban.Worker
  import Edenflowers.Actors

  alias Edenflowers.Store.{Order, Promotion}

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
    |> Order.get_by_id(load: :promotion_applied?, actor: system_actor())
    |> case do
      {:ok, order} ->
        increment_usage(order)

      {:error, _} ->
        {:error, "Order not found"}
    end
  end

  def increment_usage(%Order{promotion_applied?: true, promotion_id: promotion_id}) do
    promotion_id
    |> Promotion.increment_usage(actor: system_actor())
    |> case do
      {:ok, promotion} ->
        {:ok, promotion}

      {:error, _} ->
        {:error, "Could not increment promotion count"}
    end
  end

  def increment_usage(_), do: {:ok, nil}
end
