defmodule Edenflowers.Expenses.ExpenseImport.Changes.Process do
  @moduledoc """
  Turns a Papra receipt into a stored expense: fetches the document bytes from
  Papra, extracts structured fields via Claude, and ingests them into the
  `Edenflowers.Expenses` domain. `Expenses.ingest_expense` upserts on
  `document_id`, so a retry after a partial failure cannot duplicate the expense.
  """
  use Ash.Resource.Change

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Expenses

  defp papra, do: Application.get_env(:edenflowers, :papra_client, Edenflowers.Papra)
  defp claude, do: Application.get_env(:edenflowers, :claude_client, Edenflowers.Claude)

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      %{document_id: document_id, organization_id: organization_id} = changeset.data

      with {:ok, document} <- papra().fetch_document(organization_id, document_id),
           {:ok, fields} <- claude().extract_expense(document.body, document.content_type),
           {:ok, expense} <- Expenses.ingest_expense(Map.put(fields, :document_id, document_id), actor: system_actor()) do
        Logger.info("Processed expense document #{document_id}")

        changeset
        |> Ash.Changeset.force_change_attribute(:expense_id, expense.id)
        |> Ash.Changeset.force_change_attribute(:processed_at, DateTime.utc_now())
      else
        {:error, error} ->
          Logger.error("Failed to process expense document #{document_id}: #{inspect(error)}")
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
