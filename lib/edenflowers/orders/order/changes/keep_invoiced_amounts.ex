defmodule Edenflowers.Orders.Order.Changes.KeepInvoicedAmounts do
  @moduledoc """
  Lets Jennie edit an order an issued invoice covers (`invoiced?`) only in
  ways that keep that invoice true: its amount per VAT rate, its date of
  supply and the order's invoice terms. Renaming a line, or a new address
  that keeps the fee, is fine; anything else waits until she credits the
  invoice.

  The amounts are compared once the lines are saved and the VAT breakdown
  refreshed, so it goes after `RecordEnteredLineItems`; refusing then rolls
  the whole edit back.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.before_action(&refuse_date_or_terms/1)
    |> Ash.Changeset.after_action(&refuse_changed_amounts/2)
  end

  # Read fresh, so an invoice issued since the form opened still counts.
  defp refuse_date_or_terms(changeset) do
    invoiced? = Ash.load!(changeset.data, :invoiced?, authorize?: false, reuse_values?: false).invoiced?
    changeset = Ash.Changeset.set_context(changeset, %{invoiced?: invoiced?})

    if invoiced?,
      do: Enum.reduce([:fulfillment_date, :payment_terms], changeset, &refuse_change/2),
      else: changeset
  end

  defp refuse_change(field, changeset) do
    if Ash.Changeset.get_attribute(changeset, field) == Map.fetch!(changeset.data, field),
      do: changeset,
      else: Ash.Changeset.add_error(changeset, field: field, message: ~t"Credit the invoice first")
  end

  defp refuse_changed_amounts(changeset, order) do
    if changeset.context[:invoiced?] and amounts(order.vat_breakdown) != amounts(changeset.data.vat_breakdown) do
      {:error,
       Ash.Error.Changes.InvalidChanges.exception(
         message: ~t"Credit the invoice first: this edit changes what it bills for each VAT rate."
       )}
    else
      {:ok, order}
    end
  end

  defp amounts(rows),
    do: rows |> List.wrap() |> Enum.map(&{Decimal.normalize(&1.rate), Decimal.normalize(&1.gross)}) |> Enum.sort()
end
