defmodule Edenflowers.Expenses.Actions.ForgetDocument do
  @moduledoc """
  Deletes everything recorded for a Papra document: its expense, and its import
  even when it never became one (still pending, or failed), so a restored or
  re-uploaded document is imported again.
  """
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Edenflowers.Expenses.Expense
  alias Edenflowers.Expenses.ExpenseImport

  @impl true
  def run(input, _opts, context) do
    document_id = input.arguments.document_id

    with :ok <- destroy_all(Expense, document_id, context) do
      destroy_all(ExpenseImport, document_id, context)
    end
  end

  defp destroy_all(resource, id, context) do
    result =
      resource
      |> Ash.Query.filter(document_id == ^id)
      |> Ash.bulk_destroy(
        :destroy,
        %{},
        Ash.Context.to_opts(context, strategy: [:atomic, :stream], notify?: true, return_errors?: true)
      )

    case result do
      %Ash.BulkResult{status: :success} -> :ok
      %Ash.BulkResult{errors: errors} -> {:error, errors}
    end
  end
end
