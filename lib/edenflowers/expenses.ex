defmodule Edenflowers.Expenses do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain, AshAi]

  admin do
    show?(true)
  end

  tools do
    tool :list_expenses, Edenflowers.Expenses.Expense, :admin_list do
      description "Expenses extracted from receipts and invoices, unreviewed first. confidence is how sure the extraction was."
      select [:id, :vendor_name, :date, :total_amount, :vat_amount, :currency, :category, :description, :confidence]
      load [:reviewed]
    end

    tool :mark_expense_reviewed, Edenflowers.Expenses.Expense, :mark_reviewed do
      select [:id, :vendor_name, :reviewed_at]
    end
  end

  resources do
    resource Edenflowers.Expenses.Expense do
      define :ingest_expense, action: :ingest
      define :mark_expense_reviewed, action: :mark_reviewed
      define :correct_expense, action: :correct
    end
  end
end
