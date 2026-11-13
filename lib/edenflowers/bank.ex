defmodule Edenflowers.Bank do
  @moduledoc """
  The shop's S-Pankki account, read through Enable Banking.

  `Connection` holds the consent Jennie gives by logging in to her bank. Its
  booked payments mark expenses and invoices paid. `Transaction` keeps the
  payments out, so Jennie can see which have no receipt.
  """

  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Bank.Connection do
      define :current_bank_connection, action: :current, not_found_error?: false
      define :bank_authorization_url, action: :authorization_url, args: [:state, :redirect_url]
      define :connect_bank, action: :connect, args: [:code]
      define :sync_bank_payments, action: :sync_payments
      define :record_bank_balance, action: :record_balance
      define :booked_bank_transactions, action: :booked_transactions, args: [:date_from, :date_to]
    end

    resource Edenflowers.Bank.Transaction do
      define :record_bank_transaction, action: :record
      define :match_bank_receipts, action: :match_receipts
      define :bank_transactions_awaiting_receipt, action: :awaiting_receipt
      define :bank_payments_missing_receipt, action: :missing_receipt
      define :dismissed_bank_payments, action: :dismissed
      define :dismiss_bank_payment, action: :dismiss
      define :restore_bank_payment, action: :restore
    end
  end
end
