defmodule Edenflowers.Expenses do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Expenses.Expense do
      define :ingest_expense, action: :ingest
      define :list_expenses, action: :read
      define :mark_expense_reviewed, action: :mark_reviewed
      define :correct_expense, action: :correct
    end
  end
end
