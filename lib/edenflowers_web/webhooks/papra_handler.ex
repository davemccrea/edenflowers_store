defmodule EdenflowersWeb.Webhooks.PapraHandler do
  @moduledoc """
  Handles verified Papra webhook events.

  Every document created in Papra is a receipt or invoice, so each one is
  recorded for extraction. A document moved to Papra's trash (`document:deleted`)
  takes its expense with it. Returns quickly. AshOban performs the slow,
  fallible work with retries, and its scheduler recovers missing jobs from the
  persisted import.

  Returns `:ok` when the event was handled (or deliberately ignored) and
  `:error` when the caller should treat the delivery as failed.
  """
  require Logger

  import Edenflowers.Actors

  alias Edenflowers.Expenses

  def handle_event(%{"type" => "document:created", "data" => data}) do
    with {:ok, document_id} <- fetch(data, "documentId"),
         {:ok, organization_id} <- fetch(data, "organizationId"),
         {:ok, _import} <-
           Expenses.record_expense_import(
             %{document_id: document_id, organization_id: organization_id},
             actor: system_actor()
           ) do
      :ok
    else
      {:error, {:missing_field, field}} ->
        Logger.warning("Papra document:created event missing #{field}")
        :error

      {:error, error} ->
        Logger.error("Failed to record expense import: #{inspect(error)}")
        :error
    end
  end

  def handle_event(%{"type" => "document:deleted", "data" => data}) do
    with {:ok, document_id} <- fetch(data, "documentId"),
         :ok <- Expenses.forget_expense_document(document_id, actor: system_actor()) do
      :ok
    else
      {:error, {:missing_field, field}} ->
        Logger.warning("Papra document:deleted event missing #{field}")
        :error

      {:error, error} ->
        Logger.error("Failed to forget deleted Papra document: #{inspect(error)}")
        :error
    end
  end

  def handle_event(%{"type" => type}) do
    Logger.info("Ignoring Papra event: #{type}")
    :ok
  end

  defp fetch(data, field) do
    case Map.get(data, field) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_field, field}}
    end
  end
end
