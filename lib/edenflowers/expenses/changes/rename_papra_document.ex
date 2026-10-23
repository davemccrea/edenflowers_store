defmodule Edenflowers.Expenses.Changes.RenamePapraDocument do
  @moduledoc """
  Names the expense's Papra document after its receipt date and vendor, such as
  "2026-10-23 Kukkatukku Oy.pdf", once both are known and whenever either
  changes. A failed rename is only logged: the expense is still saved, and the
  next change to the date or vendor tries again.
  """
  use Ash.Resource.Change

  require Logger

  alias Edenflowers.External.PapraAPI

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :date) or
         Ash.Changeset.changing_attribute?(changeset, :vendor_name) do
      Ash.Changeset.after_transaction(changeset, fn
        _changeset, {:ok, expense} ->
          rename(expense)
          {:ok, expense}

        _changeset, error ->
          error
      end)
    else
      changeset
    end
  end

  defp rename(%{date: nil}), do: :ok
  defp rename(%{vendor_name: nil}), do: :ok

  defp rename(expense) do
    name = "#{Date.to_iso8601(expense.date)} #{String.trim(expense.vendor_name)}.pdf"

    case PapraAPI.impl().rename_document(expense.document_id, name) do
      :ok -> :ok
      {:error, error} -> Logger.warning("Failed to rename Papra document #{expense.document_id}: #{inspect(error)}")
    end
  end
end
