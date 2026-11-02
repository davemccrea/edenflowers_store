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

    calculate :invoice_to_send?, :boolean, expr(balance > sent_open_invoices_amount) do
      description "Whether some of the Balance is still to be asked for by an invoice the customer has seen: " <>
                    "more is owed than the open invoices they were sent still ask for. Its Order details, Booking " <>
                    "confirmed and Course reminder emails then say an invoice is still to come."
    end

    calculate :invoice_overdue?, :boolean, expr(exists(invoices, overdue?)) do
      description "Whether any of its invoices is overdue: open after its due date. Its payment_overdue? " <>
                    "follows, so the Overview lists it under Payment overdue for Jennie to chase."
    end
  end

  relationships do
    has_many :open_invoices, Edenflowers.Payments.Invoice do
      description "Its Invoices not yet paid, oldest first: the ones a bank transfer can be recorded against."
      filter expr(status == :open)
      sort number: :asc
    end

    has_many :sent_open_invoices, Edenflowers.Payments.Invoice do
      description "Its open Invoices that were emailed to the customer, oldest first: the ones its emails can " <>
                    "point to, as the customer has them. One Jennie made but hasn't sent is news to them."

      filter expr(status == :open and not is_nil(sent_at))
      sort number: :asc
    end
  end

  aggregates do
    # Only what is still unpaid: the Balance has already dropped by what was
    # paid on an open invoice, so counting it in full would count that twice.
    sum :open_invoices_amount, :open_invoices, :amount_unpaid do
      description "What open invoices still ask for in euros: the part of the Balance already invoiced. Paid " <>
                    "invoices count for nothing."

      default Decimal.new("0")
    end

    sum :sent_open_invoices_amount, :sent_open_invoices, :amount_unpaid do
      description "What the open invoices the customer was sent still ask for in euros."
      default Decimal.new("0")
    end

    count :sent_open_invoice_count, :sent_open_invoices do
      description "How many open invoices the customer was sent, so an email can say invoice or invoices."
    end
  end
end
