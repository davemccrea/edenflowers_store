defmodule Edenflowers.Orders.Order.Validations.VoucherStyleOffered do
  @moduledoc "Refuses a voucher style customers can't choose online right now (`ShopCalendar.online_voucher_styles`)."
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    style = Ash.Changeset.get_attribute(changeset, :voucher_style)

    if is_nil(style) or style in online_voucher_styles() do
      :ok
    else
      {:error, field: :voucher_style, message: ~t"The Christmas voucher isn't available right now."}
    end
  end

  defp online_voucher_styles do
    Edenflowers.Fulfillment.get_shop_calendar!(authorize?: false)
    |> Ash.load!(:online_voucher_styles, authorize?: false)
    |> Map.fetch!(:online_voucher_styles)
  end
end
