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
    end

    resource Edenflowers.Expenses.Expense do
      define :ingest_expense, action: :ingest
      define :mark_expense_reviewed, action: :mark_reviewed
      define :correct_expense, action: :correct
    end
  end
end
