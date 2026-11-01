defmodule Edenflowers.Expenses.Changes.UpdatePapraDocument do
  @moduledoc """
  Keeps the expense's Papra document in step with its receipt date and vendor,
  whenever either changes. Papra gets the receipt date as its document date, and
  once both are known the document is named after them, such as
  "2026-10-23 Kukkatukku Oy.pdf". A failed update is only logged: the expense is
  still saved, and the next change to the date or vendor tries again.
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
          update(expense)
          {:ok, expense}

        _changeset, error ->
          error
      end)
    else
      changeset
    end
  end

  defp update(%{date: nil}), do: :ok

  defp update(expense) do
    case PapraAPI.impl().update_document(expense.document_id, fields(expense)) do
      :ok -> :ok
      {:error, error} -> Logger.warning("Failed to update Papra document #{expense.document_id}: #{inspect(error)}")
    end
  end

  defp fields(%{vendor_name: nil, date: date}), do: %{documentDate: Date.to_iso8601(date)}

  defp fields(%{vendor_name: vendor_name, date: date}) do
    %{documentDate: Date.to_iso8601(date), name: "#{Date.to_iso8601(date)} #{file_safe(vendor_name)}.pdf"}
  end

  # "MailerLite Ltd." would otherwise become "MailerLite Ltd..pdf".
  defp file_safe(vendor_name), do: vendor_name |> String.trim() |> String.trim_trailing(".")
end
