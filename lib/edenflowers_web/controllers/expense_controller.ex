defmodule EdenflowersWeb.ExpenseController do
  use EdenflowersWeb, :controller

  alias Edenflowers.Expenses.Expense

  def create(conn, params) do
    attrs = %{
      document_id: params["document_id"],
      vendor_name: params["vendor_name"],
      vendor_vat_number: params["vendor_vat_number"],
      date: params["date"],
      total_amount: params["total_amount"],
      vat_amount: params["vat_amount"],
      currency: params["currency"],
      category: params["category"],
      description: params["description"],
      confidence: params["confidence"],
      processed_at: params["processed_at"] || DateTime.utc_now()
    }

    case Expense.ingest(attrs, actor: %{system: true}) do
      {:ok, expense} ->
        conn
        |> put_status(:created)
        |> json(%{id: expense.id, document_id: expense.document_id})

      {:error, %Ash.Error.Invalid{} = error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(error)})
    end
  end
end
