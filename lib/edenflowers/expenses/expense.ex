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
    migration_types total_amount: :decimal, vat_amount: :decimal

    check_constraints do
      check_constraint :total_amount, "expenses_valid_total_amount",
        check: "total_amount = round(total_amount, 2)",
        message: "must be an amount in whole cents"

      check_constraint :vat_amount, "expenses_valid_vat_amount",
        check: "vat_amount = round(vat_amount, 2)",
        message: "must be an amount in whole cents"
    end
  end

  actions do
    defaults [:read, :destroy]

    read :admin_list do
      pagination offset?: true, keyset?: true, countable: true, required?: false
      prepare build(sort: [reviewed: :asc, date: :desc_nils_first, processed_at: :desc])
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
    attribute :total_amount, :decimal, constraints: [scale: 2]
    attribute :vat_amount, :decimal, constraints: [scale: 2]
    attribute :currency, Currency
    attribute :category, Category
    attribute :description, :string
    attribute :confidence, Confidence, allow_nil?: false
    attribute :processed_at, :utc_datetime, allow_nil?: false
    attribute :reviewed_at, :utc_datetime

    timestamps()
  end

  calculations do
    calculate :reviewed, :boolean, expr(not is_nil(reviewed_at))
  end

  identities do
    identity :unique_document_id, [:document_id]
  end
end
