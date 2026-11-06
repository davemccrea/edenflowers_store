defmodule Edenflowers.Payments.GiftVoucherStyle do
  @moduledoc """
  How a Gift voucher's PDF looks, chosen when it's sold. `:cream` prints well at
  home and is the default. `:green` fills the page with the brand green, so it
  suits a voucher that's forwarded more than printed. `:christmas` is cream with
  snowflakes and a Christmas greeting; customers can only choose it online while
  Jennie offers it (`ShopCalendar.christmas_vouchers_online`).
  """
  use Ash.Type.Enum, values: [:cream, :green, :christmas]
end
