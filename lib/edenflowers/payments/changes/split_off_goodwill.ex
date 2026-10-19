defmodule Edenflowers.Payments.Changes.SplitOffGoodwill do
  @moduledoc """
  Splits a Stripe refund's negative `amount` into the part that was owed back,
  `owed_back`, and the rest, `goodwill_refund`, handed back on top. Either is
  left unset when it's nothing. A `goodwill` argument of true or false says
  it's all one or the other.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case {Ash.Changeset.get_argument(changeset, :amount), Ash.Changeset.get_argument(changeset, :goodwill)} do
      {%Decimal{} = amount, true} ->
        Ash.Changeset.set_argument(changeset, :goodwill_refund, amount)

      {%Decimal{} = amount, false} ->
        Ash.Changeset.set_argument(changeset, :owed_back, amount)

      {%Decimal{} = amount, nil} ->
        record = Ash.load!(changeset.data, :balance, authorize?: false, reuse_values?: false)
        owed_back = Decimal.max(amount, Decimal.min(record.balance, 0))

        changeset
        |> set_unless_zero(:owed_back, owed_back)
        |> set_unless_zero(:goodwill_refund, Decimal.sub(amount, owed_back))

      _invalid ->
        changeset
    end
  end

  defp set_unless_zero(changeset, argument, amount) do
    if Decimal.eq?(amount, 0), do: changeset, else: Ash.Changeset.set_argument(changeset, argument, amount)
  end
end
