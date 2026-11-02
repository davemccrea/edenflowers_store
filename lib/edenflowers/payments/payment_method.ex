defmodule Edenflowers.Payments.PaymentMethod do
  @moduledoc """
  How an order or course booking was paid. `:stripe` covers checkout and the payment link,
  card or MobilePay alike, and is recorded from Stripe. Jennie records the rest herself;
  `:mobilepay` is her own MobilePay number, outside Stripe, and `:zervant` is a bank
  transfer paying an invoice, usually one of the shop's own `Invoice`s.

  `:zervant` keeps its name from when invoices were sent from Zervant: it is the
  value stored on existing payments, and renaming it would need a hand-written data
  migration. Shown as "Bank transfer".
  """
  use Ash.Type.Enum, values: [:stripe, :zettle, :mobilepay, :cash, :zervant]
end
