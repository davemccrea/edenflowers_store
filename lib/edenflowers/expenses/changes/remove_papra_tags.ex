defmodule Edenflowers.Expenses.Changes.RemovePapraTags do
  @moduledoc """
  Removes the receipt and processed tags from the expense's Papra document
  before the expense is deleted. If Papra can't be reached, the delete fails
  rather than leaving a tagged document with no expense behind it.
  """
  use Ash.Resource.Change

  require Logger

  alias Edenflowers.External.PapraAPI

  defp papra, do: Application.get_env(:edenflowers, :papra_api, PapraAPI)

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      document_id = changeset.data.document_id

      with :ok <- papra().remove_document_tag(document_id, PapraAPI.receipt_tag()),
           :ok <- papra().remove_document_tag(document_id, PapraAPI.processed_tag()) do
        changeset
      else
        {:error, error} ->
          Logger.error("Failed to remove tags from Papra document #{document_id}: #{inspect(error)}")
          Ash.Changeset.add_error(changeset, "Couldn't remove the tags in Papra")
      end
    end)
  end
end
