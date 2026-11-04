defmodule Edenflowers.Payments.Changes.RecordInvoicePayment do
  @moduledoc "Records standalone receipts or their reversals within the locked invoice transaction."
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.Payment

  @impl true
  def change(changeset, opts, _context) do
    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      invoice = Invoice.get_locked(changeset.data.id, [:status, :amount_unpaid])

      cond do
        is_nil(invoice) or invoice.status in [:draft, :cancelled] ->
          Ash.Changeset.add_error(changeset, "Only issued, uncredited invoices can receive payments")

        overpaid?(changeset, invoice, Keyword.get(opts, :reversal?, false)) ->
          Ash.Changeset.add_error(changeset, field: :amount, message: ~t"That's more than is owed.")

        true ->
          %{changeset | data: invoice}
      end
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

  # Checked under the invoice lock, so two receipts entered at once can't both fit.
  defp overpaid?(_changeset, _invoice, true = _reversal?), do: false

  defp overpaid?(changeset, invoice, false),
    do: Decimal.gt?(Ash.Changeset.get_argument(changeset, :amount), invoice.amount_unpaid)

  defp attributes(changeset, false) do
    {:ok,
     %{
       amount: Ash.Changeset.get_argument(changeset, :amount),
       bank_transaction_id: Ash.Changeset.get_argument(changeset, :bank_transaction_id)
     }}
  end

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
