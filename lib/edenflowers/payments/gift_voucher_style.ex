defmodule Edenflowers.Payments.GiftVoucherStyle do
  @moduledoc """
  How a Gift voucher's PDF looks, chosen when it's sold. `:cream` (Signature to
  customers) is the default. `:golden_hour` puts a flower photo on the stub
  instead of green. `:christmas` (Christmas red) and `:christmas_green` are cream
  with snowflakes and a Christmas greeting, in one cranberry or green accent;
  customers can only choose them online while Jennie offers them
  (`ShopCalendar.online_voucher_styles`).
  """
  use Ash.Type.Enum, values: [:cream, :golden_hour, :christmas, :christmas_green]

  @doc "Whether a style is one of the Christmas ones, from its atom or its form value."
  def christmas?(style), do: to_string(style) in ~w(christmas christmas_green)
end
