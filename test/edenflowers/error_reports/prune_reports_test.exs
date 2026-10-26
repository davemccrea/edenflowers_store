defmodule Edenflowers.ErrorReports.PruneReportsTest do
  use Edenflowers.DataCase, async: true

  alias Edenflowers.ErrorReports.PruneReports
  alias Edenflowers.Repo

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days, :day)

  defp insert_error(days) do
    Repo.insert!(%ErrorTracker.Error{
      kind: "error",
      reason: "boom",
      source_line: "lib/x.ex:1",
      source_function: "X.run/1",
      status: :unresolved,
      fingerprint: "fingerprint-#{days}",
      muted: false,
      last_occurrence_at: days_ago(days)
    })
  end

  defp insert_occurrence(error, days) do
    Repo.insert!(%ErrorTracker.Occurrence{
      error_id: error.id,
      reason: "boom",
      context: %{"ip" => "192.0.2.1"},
      stacktrace: %ErrorTracker.Stacktrace{lines: []},
      inserted_at: days_ago(days)
    })
  end

  test "deletes unresolved errors once their last report is older than 90 days" do
    stale = insert_error(91)
    recent = insert_error(89)

    assert :ok = perform_job(PruneReports, %{})

    assert Repo.get(ErrorTracker.Error, stale.id) == nil
    assert Repo.get(ErrorTracker.Error, recent.id)
  end

  test "deletes old reports of an error that is still recurring" do
    error = insert_error(0)
    old = insert_occurrence(error, 91)
    new = insert_occurrence(error, 10)

    assert :ok = perform_job(PruneReports, %{})

    assert Repo.get(ErrorTracker.Occurrence, old.id) == nil
    assert Repo.get(ErrorTracker.Occurrence, new.id)
    assert Repo.get(ErrorTracker.Error, error.id)
  end

  test "deletes an expired error with the reports that are still attached to it" do
    error = insert_error(120)
    old = insert_occurrence(error, 120)

    assert :ok = perform_job(PruneReports, %{})

    assert Repo.get(ErrorTracker.Error, error.id) == nil
    assert Repo.get(ErrorTracker.Occurrence, old.id) == nil
  end

  test "keeps errors that were resolved recently, and runs again without failing" do
    resolved = insert_error(91) |> Ecto.Changeset.change(status: :resolved) |> Repo.update!()

    assert :ok = perform_job(PruneReports, %{})
    assert Repo.get(ErrorTracker.Error, resolved.id) == nil

    assert :ok = perform_job(PruneReports, %{})
  end
end
