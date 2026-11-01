defmodule Edenflowers.Payments.Validations.InvoiceOfPurchase do
  @moduledoc """
  A Payment can only pay an Invoice of the order or Course booking it is for,
  so money on one purchase never settles another's Invoice, and never one a
  Credit note has cancelled.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  alias Edenflowers.Payments.Invoice

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :invoice_id) do
      nil ->
        :ok

      invoice_id ->
        invoice = Ash.get!(Invoice, invoice_id, load: [:status], authorize?: false, not_found_error?: false)

        cond do
          !invoice || !same_purchase?(invoice, changeset) ->
            {:error, field: :invoice_id, message: ~t"That invoice isn't for this purchase."}

          invoice.status == :cancelled ->
            {:error, field: :invoice_id, message: ~t"That invoice is cancelled."}

          true ->
            :ok
        end
    end
  end

  defp same_purchase?(invoice, changeset) do
    {invoice.order_id, invoice.course_registration_id} ==
      {Ash.Changeset.get_attribute(changeset, :order_id),
       Ash.Changeset.get_attribute(changeset, :course_registration_id)}
  end
end
