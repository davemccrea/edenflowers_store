defmodule Edenflowers.Expenses.Expense.Category do
  use Ash.Type.Enum,
    values: [
      :office_supplies,
      :travel,
      :meals,
      :software,
      :marketing,
      :utilities,
      :professional_services,
      :other
    ]
end

defmodule Edenflowers.Expenses.Expense.Confidence do
  use Ash.Type.Enum, values: [:high, :medium, :low]
end

defmodule Edenflowers.Expenses.Expense.Currency do
  use Ash.Type.Enum, values: [:eur, :sek]
end

defmodule Edenflowers.Expenses.Expense do
  use Ash.Resource,
    domain: Edenflowers.Expenses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Edenflowers.Expenses.Expense.{Category, Confidence, Currency}

  postgres do
    table "expenses"
    repo Edenflowers.Repo
  end

  code_interface do
    define :ingest, action: :ingest
    define :list, action: :read
    define :list_needs_review, action: :needs_review
    define :mark_reviewed, action: :mark_reviewed
    define :correct, action: :correct
  end

  actions do
    defaults [:read, :destroy]

    read :needs_review do
      filter expr(is_nil(reviewed_at) and confidence != :high)
      prepare build(sort: [date: :desc])
    end

    create :ingest do
      description "Upserts an expense record extracted from a receipt/invoice document."
      upsert? true
      upsert_identity :unique_document_id

      upsert_fields [
        :vendor_name,
        :vendor_vat_number,
        :date,
        :total_amount,
        :vat_amount,
        :currency,
        :category,
        :description,
        :confidence,
        :processed_at
      ]

      accept [
        :document_id,
        :vendor_name,
        :vendor_vat_number,
        :date,
        :total_amount,
        :vat_amount,
        :currency,
        :category,
        :description,
        :confidence
      ]

      change set_attribute(:processed_at, &DateTime.utc_now/0)
    end

    update :mark_reviewed do
      description "Records when an admin has reviewed this expense."
      change set_attribute(:reviewed_at, &DateTime.utc_now/0)
    end

    update :correct do
      description "Corrects fields that were mis-extracted by the LLM."
      accept [:vendor_name, :vendor_vat_number, :date, :total_amount, :vat_amount, :currency, :category, :description]
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if action(:ingest)
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :document_id, :string, allow_nil?: false
    attribute :vendor_name, :string
    attribute :vendor_vat_number, :string
    attribute :date, :date
    attribute :total_amount, :decimal
    attribute :vat_amount, :decimal
    attribute :currency, Currency
    attribute :category, Category
    attribute :description, :string
    attribute :confidence, Confidence, allow_nil?: false
    attribute :processed_at, :utc_datetime, allow_nil?: false
    attribute :reviewed_at, :utc_datetime

    timestamps()
  end

  identities do
    identity :unique_document_id, [:document_id]
  end
end
