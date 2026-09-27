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
      import = changeset.data

      with {:ok, document} <- fetch(import.document_id, import.organization_id),
           {:ok, fields} <- extract(import.document_id, document),
           {:ok, expense} <- ingest(import.document_id, fields) do
        Logger.info("Processed expense document #{import.document_id}")

        changeset
        |> Ash.Changeset.force_change_attribute(:expense_id, expense.id)
        |> Ash.Changeset.force_change_attribute(:processed_at, DateTime.utc_now())
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  defp fetch(document_id, organization_id) do
    case papra().fetch_document(organization_id, document_id) do
      {:ok, document} ->
        {:ok, document}

      {:error, reason} = error ->
        Logger.error("Failed to fetch Papra document #{document_id}: #{inspect(reason)}")
        error
    end
  end

  defp extract(document_id, %{body: body, content_type: content_type}) do
    case claude().extract_expense(body, content_type) do
      {:ok, fields} ->
        {:ok, fields}

      {:error, reason} = error ->
        Logger.error("Failed to extract expense data from document #{document_id}: #{inspect(reason)}")
        error
    end
  end

  defp ingest(document_id, fields) do
    attrs = Map.put(fields, :document_id, document_id)

    case Expenses.ingest_expense(attrs, actor: system_actor()) do
      {:ok, expense} ->
        {:ok, expense}

      {:error, reason} = error ->
        Logger.error("Failed to ingest expense for document #{document_id}: #{inspect(reason)}")
        error
    end
  end
end
