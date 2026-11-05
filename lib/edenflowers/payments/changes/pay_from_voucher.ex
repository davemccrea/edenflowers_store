defmodule Edenflowers.Payments.Changes.PayFromVoucher do
  @moduledoc """
  Pays what's still owed from the order's or booking's Gift voucher, as far as
  what's left on it goes: one `:voucher` `Payment` of min(what's left,
  Balance). Runs after any Stripe payment the action records, so the voucher
  pays only what the card didn't.

  The voucher row is locked first, so two purchases placed at once can't
  both spend the same money. One spent or expired since checkout showed it
  pays what it still can, and the rest is left as a Balance for Jennie, as
  any payment that doesn't match is (ADR 0002).
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Payments
  alias Edenflowers.Payments.Changes.RecordPayment
  alias Edenflowers.Payments.GiftVoucher
  alias Edenflowers.Payments.Payment

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      case record.gift_voucher_id do
        nil -> {:ok, record}
        voucher_id -> pay(record, voucher_id)
      end
    end)
  end

  defp pay(record, voucher_id) do
    with {:ok, voucher} <- lock(voucher_id),
         {:ok, record} <- Ash.load(record, :balance, authorize?: false, reuse_values?: false) do
      case amount(voucher, record.balance) do
        :none -> {:ok, record}
        amount -> record_payment(record, voucher, amount)
      end
    end
  end

  defp lock(voucher_id) do
    with {:ok, voucher} <-
           GiftVoucher
           |> Ash.Query.filter(id == ^voucher_id)
           |> Ash.Query.lock(:for_update)
           |> Ash.read_one(authorize?: false) do
      Ash.load(voucher, [:remaining, :spendable?], authorize?: false)
    end
  end

  defp amount(%{spendable?: false}, _balance), do: :none

  defp amount(voucher, balance) do
    if Decimal.positive?(balance), do: Decimal.min(voucher.remaining, balance), else: :none
  end

  defp record_payment(record, voucher, amount) do
    payment =
      Payment
      |> Ash.Changeset.for_create(:record, %{
        Payments.parent_key(record) => record.id,
        amount: amount,
        method: :voucher,
        payment_method_type: "voucher",
        gift_voucher_id: voucher.id
      })
      |> Ash.create(authorize?: false)

    with {:ok, _payment} <- payment, do: RecordPayment.reload(record)
  end
end
