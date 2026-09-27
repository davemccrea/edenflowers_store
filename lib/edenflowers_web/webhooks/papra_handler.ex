defmodule EdenflowersWeb.Webhooks.PapraHandler do
  @moduledoc """
  Handles verified Papra webhook events.

  Records receipt imports and returns quickly. AshOban performs the slow,
  fallible work with retries, and its scheduler recovers missing jobs from the
  persisted import.

  Returns `:ok` when the event was handled (or deliberately ignored) and
  `:error` when the caller should treat the delivery as failed.
  """
  require Logger

  import Edenflowers.Actors

  alias Edenflowers.Expenses

  @receipt_tag "receipt"

  def handle_event(%{"type" => "document:tag:added", "data" => %{"tagName" => @receipt_tag} = data}) do
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
        Logger.warning("Papra document:tag:added event missing #{field}")
        :error

      {:error, error} ->
        Logger.error("Failed to record expense import: #{inspect(error)}")
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
