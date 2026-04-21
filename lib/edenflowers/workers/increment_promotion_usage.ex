defmodule Edenflowers.Workers.IncrementPromotionUsage do
  use Oban.Worker
  import Edenflowers.Actors

  alias Edenflowers.Store.Promotion

  def enqueue(%{"promotion_id" => promotion_id} = args) do
    args
    |> __MODULE__.new()
    |> Oban.insert()
    |> case do
      {:ok, job} -> {:ok, job}
      {:error, changeset} -> {:error, {:enqueue_failed, promotion_id, changeset}}
    end
  end

  def perform(%Oban.Job{args: %{"promotion_id" => promotion_id}}) do
    case Promotion.increment_usage(promotion_id, actor: system_actor()) do
      {:ok, _promotion} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
