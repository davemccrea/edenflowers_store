defmodule Edenflowers.Payments.Changes.RequireSettled do
  @moduledoc """
  Refuses, rolling the whole action back, unless the order or booking is
  left with nothing to collect. For placing a purchase without Stripe, where
  a Gift voucher must have paid it all.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      record = Ash.load!(record, :balance, authorize?: false, reuse_values?: false)

      if Decimal.positive?(record.balance),
        do: {:error, Ash.Error.Changes.InvalidChanges.exception(message: ~t"Your gift voucher no longer covers this.")},
        else: {:ok, record}
    end)
  end
end
