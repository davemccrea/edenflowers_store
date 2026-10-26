defmodule Edenflowers.ErrorReports.PruneReports do
  @moduledoc """
  Deletes error reports older than the 90 days the privacy notice promises.

  ErrorTracker's own pruner only removes errors someone marked resolved, so an
  unresolved error would keep its occurrences, contexts and headers forever.
  This deletes by age alone, whatever the status. Occurrences go first: an
  error that keeps recurring loses its old reports but stays in the dashboard.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias Edenflowers.Repo
  alias ErrorTracker.Error
  alias ErrorTracker.Occurrence

  @retention_days 90
  @batch_size 500

  @impl true
  def perform(_job) do
    cutoff = DateTime.add(DateTime.utc_now(), -@retention_days, :day)

    prune_occurrences(cutoff)
    prune_errors(cutoff)
  end

  defp prune_occurrences(cutoff) do
    Occurrence
    |> where([occurrence], occurrence.inserted_at < ^cutoff)
    |> select([occurrence], occurrence.id)
    |> Repo.all()
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(&delete_occurrences/1)
  end

  defp prune_errors(cutoff) do
    Error
    |> where([error], error.last_occurrence_at < ^cutoff)
    |> select([error], error.id)
    |> Repo.all()
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(&delete_errors/1)
  end

  defp delete_occurrences(ids) do
    Repo.delete_all(from occurrence in Occurrence, where: occurrence.id in ^ids)
  end

  defp delete_errors(ids) do
    Repo.delete_all(from error in Error, where: error.id in ^ids)
  end
end
