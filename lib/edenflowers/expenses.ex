defmodule Edenflowers.Expenses do
  @moduledoc """
  Entry point for expenses imported from Papra.

  `ExpenseImport` tracks a document through extraction and retries; `Expense`
  stores the classified figures Jennie can review and correct in admin.
  """

  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Expenses.ExpenseImport do
      define :record_expense_import, action: :record
      define :forget_expense_document, action: :forget_document, args: [:document_id]
      define :import_invoice_emails, action: :import_invoice_emails
    end

    resource Edenflowers.Expenses.Expense do
      define :ingest_expense, action: :ingest
      define :correct_expense, action: :correct
      define :mark_expense_unpaid, action: :mark_unpaid
      define :list_expenses_unpaid_at, action: :unpaid_at, args: [:date]

      define :expenses_awaiting_bank_payment,
        action: :awaiting_bank_payment,
        args: [:reference_number, :amount, :currency]

      define :expenses_awaiting_unreferenced_bank_payment,
        action: :awaiting_unreferenced_bank_payment,
        args: [:amount, :currency, :booked_on]

      define :mark_expense_paid_from_bank, action: :paid_from_bank, args: [:booked_on]

      define :expenses_paid_near_bank_payment,
        action: :paid_near_bank_payment,
        args: [:bank_transaction_id, :amount, :currency, :booked_on]

      define :expenses_linkable_by_hand, action: :linkable_by_hand, args: [:booked_on, :amount, :currency]
      define :link_expense_bank_payment, action: :link_bank_payment, args: [:booked_on, :bank_transaction_id]
      define :unlink_expense_bank_payment, action: :unlink_bank_payment

      define :settle_expense_from_bank,
        action: :settle_from_bank,
        args: [:reference_number, :amount, :currency, :booked_on]
    end
  end
end
