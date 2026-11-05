defmodule Edenflowers.Payments.Changes.ApplyGiftVoucher do
  @moduledoc """
  Puts the Gift voucher named by the `code` argument on a cart or a course
  checkout, so Stripe is asked to charge only what it doesn't cover. Nothing
  is spent yet: `PayFromVoucher` pays from it once the purchase is placed or
  confirmed.

  Refuses an unknown code, a voucher that has expired or is used up, and a
  subscription cart, whose later deliveries a voucher can't pay for yet.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      if subscription?(changeset.data),
        do: refuse(changeset, ~t"A gift voucher can't pay for a subscription yet."),
        else: apply_code(changeset, Ash.Changeset.get_argument(changeset, :code))
    end)
  end

  defp apply_code(changeset, code) do
    case Payments.get_gift_voucher_by_code(code, not_found_error?: false) do
      {:ok, %{spendable?: true} = voucher} ->
        Ash.Changeset.force_change_attribute(changeset, :gift_voucher_id, voucher.id)

      {:ok, nil} ->
        refuse(changeset, ~t"We couldn't find that gift voucher. Check the code and try again.")

      {:ok, voucher} ->
        refuse(changeset, unspendable(voucher, changeset.data))

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp subscription?(%Order{} = order), do: Ash.load!(order, :subscription?, authorize?: false).subscription?
  defp subscription?(_registration), do: false

  defp unspendable(voucher, record) do
    if voucher.expired?,
      do: ~t"This gift voucher expired on #{date = Edenflowers.Format.date(voucher.expires_on, record.locale)}.",
      else: ~t"This gift voucher has been used up."
  end

  defp refuse(changeset, message), do: Ash.Changeset.add_error(changeset, field: :code, message: message)
end
