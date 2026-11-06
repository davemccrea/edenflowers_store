defmodule Edenflowers.Orders.Order.Changes.SetGiftVoucherLine do
  @moduledoc """
  Makes a Gift voucher sale's one line the voucher for the `amount`
  argument, named in the order's language, replacing the line it had.

  `authorize?: false` for a sale Jennie places as she enters it, as
  `place_custom` does with its lines: a line can otherwise only go on an
  order not yet placed.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def change(%{valid?: false} = changeset, _opts, _context), do: changeset

  def change(changeset, opts, _context) do
    amount = Ash.Changeset.get_argument(changeset, :amount)
    locale = Ash.Changeset.get_attribute(changeset, :locale)
    name = EdenflowersWeb.Gettext.with_app_locale(locale, fn -> ~t"Gift voucher" end)

    Ash.Changeset.manage_relationship(
      changeset,
      :line_items,
      [%{unit_price: Decimal.new(amount), product_name: name}],
      on_no_match: {:create, :sell_gift_voucher},
      on_match: :ignore,
      on_missing: {:destroy, :remove_item},
      authorize?: Keyword.get(opts, :authorize?, true)
    )
  end
end
