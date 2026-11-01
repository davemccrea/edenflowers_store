defmodule Edenflowers.Payments.Invoiceable do
  @moduledoc """
  Whether an order or a Course booking can be invoiced, and what is left to
  invoice, worked out the same way for both.

  The including resource supplies `has_many :invoices`, `payment_terms`,
  `committed?`, the `Payable` Balance, and `buyer_details_complete?`: the
  buyer's name and email plus `BusinessCustomer`'s details.
  """
  use Spark.Dsl.Fragment, of: Ash.Resource

  calculations do
    calculate :invoiceable?,
              :boolean,
              expr(committed? and payment_terms == :invoice and buyer_details_complete?) do
      description "Whether Jennie can invoice it: placed or confirmed (cancelled too, to bill what she kept), on " <>
                    "invoice terms, and with the buyer's name, email and any business details filled in. " <>
                    "Validations.Invoiceable refuses an invoice otherwise."
    end

    calculate :uninvoiced_balance, :decimal, expr(balance - open_invoices_amount) do
      description "The Balance in euros not yet asked for by an open invoice: what a new invoice is for unless " <>
                    "Jennie chooses another amount. Zero or less means nothing is left to invoice."
    end
  end

  aggregates do
    # Every invoice counts in full until Payments are recorded against
    # invoices and invoices can be cancelled. Then a cancelled one counts for
    # nothing, and an open one only for what is still unpaid on it, since the
    # Balance has already dropped by what was paid.
    sum :open_invoices_amount, :invoices, :amount do
      description "What open invoices ask for in euros: the part of the Balance already invoiced."
      default Decimal.new("0")
    end
  end
end
