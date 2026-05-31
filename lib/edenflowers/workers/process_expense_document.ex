defmodule Edenflowers.Workers.ProcessExpenseDocument do
  @moduledoc """
  Turns a Papra `document:created` event into a stored expense record:
  fetches the document bytes from Papra, extracts structured fields via
  Claude, and ingests them into the `Edenflowers.Expenses` domain.

  Unique on `document_id` so at-least-once webhook delivery collapses to a
  single job. `Expense.ingest` additionally upserts on `document_id`, so even
  a job that runs twice cannot create a duplicate row.
  """
  use Oban.Worker, unique: [keys: [:document_id], period: :infinity]

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Claude
  alias Edenflowers.Papra
  alias Edenflowers.Expenses.Expense

  def enqueue(%{"document_id" => document_id} = args) do
    args
    |> __MODULE__.new()
    |> Oban.insert()
    |> case do
      {:ok, job} -> {:ok, job}
      {:error, changeset} -> {:error, {:enqueue_failed, document_id, changeset}}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"document_id" => document_id, "organization_id" => organization_id}}) do
    with {:ok, document} <- fetch(document_id, organization_id),
         {:ok, fields} <- extract(document_id, document),
         {:ok, _expense} <- ingest(document_id, fields) do
      Logger.info("Processed expense document #{document_id}")
      :ok
    end
  end

  defp fetch(document_id, organization_id) do
    case Papra.fetch_document(organization_id, document_id) do
      {:ok, document} ->
        {:ok, document}

      {:error, reason} = error ->
        Logger.error("Failed to fetch Papra document #{document_id}: #{inspect(reason)}")
        error
    end
  end

  defp extract(document_id, %{body: body, content_type: content_type}) do
    case Claude.extract_expense(body, content_type) do
      {:ok, fields} ->
        {:ok, fields}

      {:error, reason} = error ->
        Logger.error("Failed to extract expense data from document #{document_id}: #{inspect(reason)}")
        error
    end
  end

  defp ingest(document_id, fields) do
    attrs = Map.put(fields, :document_id, document_id)

    case Expense.ingest(attrs, actor: system_actor()) do
      {:ok, expense} ->
        {:ok, expense}

      {:error, reason} = error ->
        Logger.error("Failed to ingest expense for document #{document_id}: #{inspect(reason)}")
        error
    end
  end
end
