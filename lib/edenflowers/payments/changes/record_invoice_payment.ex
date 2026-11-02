defmodule Edenflowers.Payments.Changes.RecordInvoicePayment do
  @moduledoc "Records standalone receipts or their reversals within the locked invoice transaction."
  use Ash.Resource.Change

  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.Payment

  @impl true
  def change(changeset, opts, _context) do
    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      invoice = Invoice.get_locked(changeset.data.id, [:status])

      if invoice && invoice.status not in [:draft, :cancelled],
        do: %{changeset | data: invoice},
        else: Ash.Changeset.add_error(changeset, "Only issued, uncredited invoices can receive payments")
    end)
    |> Ash.Changeset.after_action(fn changeset, invoice ->
      with {:ok, attrs} <- attributes(changeset, Keyword.get(opts, :reversal?, false)),
           {:ok, _payment} <-
             Payment
             |> Ash.Changeset.for_create(
               :record,
               Map.merge(attrs, %{
                 invoice_id: invoice.id,
                 method: :zervant,
                 payment_method_type: "zervant",
                 paid_at: Ash.Changeset.get_argument(changeset, :paid_at)
               })
             )
             |> Ash.create(authorize?: false) do
        Ash.load(invoice, [:amount_paid, :amount_unpaid, :paid?, :status, :payments],
          authorize?: false,
          reuse_values?: false
        )
      end
    end)
  end

  defp attributes(changeset, false),
    do: {:ok, %{amount: Ash.Changeset.get_argument(changeset, :amount)}}

  defp attributes(changeset, true) do
    id = Ash.Changeset.get_argument(changeset, :payment_id)

    with {:ok, payment} <- Ash.get(Payment, id, load: [:undoable?], authorize?: false),
         true <- payment.invoice_id == changeset.data.id && payment.undoable?,
         true <- Decimal.positive?(payment.amount) do
      {:ok, %{amount: Decimal.negate(payment.amount), reverses_payment_id: payment.id}}
    else
      _ -> {:error, Ash.Error.Changes.InvalidArgument.exception(field: :payment_id, message: "can't be undone")}
    end
  end
end
