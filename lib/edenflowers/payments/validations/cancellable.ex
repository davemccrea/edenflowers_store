defmodule Edenflowers.Payments.Validations.Cancellable do
  @moduledoc """
  Refuses a credit note for an Invoice that isn't `cancellable?`, read
  fresh, saying why. The same calculation tells the admin whether to offer
  Cancel at all.

  An Invoice with any money on it can't be cancelled, not only a paid one:
  its Payments would then count against no open invoice. Jennie undoes them
  first, and records the money again against the new invoice.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  alias Edenflowers.Payments.Invoice

  @impl true
  def validate(changeset, _opts, _context) do
    with id when not is_nil(id) <- Ash.Changeset.get_attribute(changeset, :invoice_id),
         %Invoice{} = invoice <- Ash.get!(Invoice, id, load: load(), authorize?: false, not_found_error?: false) do
      check(invoice)
    else
      _no_invoice -> :ok
    end
  end

  defp load, do: [:cancellable?, :status, :amount_paid, credit_note: [:number]]

  defp check(%{cancellable?: true}), do: :ok

  defp check(%{status: :cancelled, credit_note: %{number: number}}),
    do: error(~t"Credit note #{number} already cancels this invoice.")

  defp check(%{status: :paid}), do: error(~t"A paid invoice can't be cancelled.")

  defp check(_part_paid),
    do: error(~t"Payments are recorded against this invoice. Undo them first, then cancel it.")

  defp error(message), do: {:error, field: :invoice_id, message: message}
end
