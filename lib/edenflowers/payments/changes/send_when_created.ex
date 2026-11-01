defmodule Edenflowers.Payments.Changes.SendWhenCreated do
  @moduledoc """
  Sends a new Invoice or Credit note through its `:send` once it is
  committed, when Jennie ticked to email it. A failed email never loses the
  document or its number; the result's `:emailed?` metadata says whether it
  went.
  """
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.get_argument(changeset, :email_customer?) do
      Ash.Changeset.after_transaction(changeset, fn
        changeset, {:ok, document} -> {:ok, send_document(document, Ash.Changeset.get_argument(changeset, :message))}
        _changeset, error -> error
      end)
    else
      changeset
    end
  end

  defp send_document(%resource{} = document, message) do
    case Ash.update(document, %{message: message}, action: :send, authorize?: false) do
      {:ok, sent} ->
        Ash.Resource.put_metadata(sent, :emailed?, true)

      {:error, error} ->
        Logger.error("#{inspect(resource)} #{document.number} (#{document.id}) not emailed: #{inspect(error)}")
        Ash.Resource.put_metadata(document, :emailed?, false)
    end
  end
end
