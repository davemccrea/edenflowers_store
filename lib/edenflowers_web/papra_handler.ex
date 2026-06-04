defmodule EdenflowersWeb.PapraHandler do
  @moduledoc """
  Handles verified Papra webhook events.

  Mirrors `EdenflowersWeb.StripeHandler`: a thin module that turns a webhook
  payload into an enqueued Oban job and returns quickly. All slow, fallible
  work (fetching the document, calling Claude, ingesting) happens in
  `Edenflowers.Workers.ProcessExpenseDocument`, where Oban retries apply.

  Returns `:ok` when the event was handled (or deliberately ignored) and
  `:error` when the caller should treat the delivery as failed.
  """
  require Logger

  alias Edenflowers.Workers.ProcessExpenseDocument

  @receipt_tag "receipt"

  def handle_event(%{"type" => "document:tag:added", "data" => %{"tagName" => @receipt_tag} = data}) do
    with {:ok, document_id} <- fetch(data, "documentId"),
         {:ok, organization_id} <- fetch(data, "organizationId"),
         {:ok, _job} <-
           ProcessExpenseDocument.enqueue(%{
             "document_id" => document_id,
             "organization_id" => organization_id
           }) do
      :ok
    else
      {:error, {:missing_field, field}} ->
        Logger.warning("Papra document:tag:added event missing #{field}")
        :error

      {:error, {:enqueue_failed, document_id, changeset}} ->
        Logger.error("Failed to enqueue expense job for document #{document_id}: #{inspect(changeset)}")
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
