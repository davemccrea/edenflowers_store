defmodule Edenflowers.Orders.Order.Validations.VoucherStyleOffered do
  @moduledoc "Refuses the Christmas voucher style online while Jennie isn't offering it."
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    if Ash.Changeset.get_attribute(changeset, :voucher_style) != :christmas or
         Edenflowers.Fulfillment.get_shop_calendar!(authorize?: false).christmas_vouchers_online do
      :ok
    else
      {:error, field: :voucher_style, message: ~t"The Christmas voucher isn't available right now."}
    end
  end
end
