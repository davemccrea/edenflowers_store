defmodule Edenflowers.Payments.GiftVoucherStyle do
  @moduledoc """
  How a Gift voucher's PDF looks, chosen when it's sold. `:cream` (Regular to
  customers) is the default. `:christmas` is cream with snowflakes and a
  Christmas greeting; customers can only choose it online while Jennie offers it
  (`ShopCalendar.christmas_vouchers_online`).
  """
  use Ash.Type.Enum, values: [:cream, :christmas]
end
