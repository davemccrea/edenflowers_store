defmodule Edenflowers.Payments.PaymentMethod do
  @moduledoc """
  How an order or course booking was paid. `:stripe` covers checkout and the payment link,
  card or MobilePay alike, and is recorded from Stripe. Jennie records the rest herself;
  `:mobilepay` is her own MobilePay number, outside Stripe, and `:zervant` is an
  invoice she sent from Zervant and was paid by bank transfer.
  """
  use Ash.Type.Enum, values: [:stripe, :zettle, :mobilepay, :cash, :zervant]
end
