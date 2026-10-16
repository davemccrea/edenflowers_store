defmodule Edenflowers.Expenses.Expense.Category do
  @moduledoc """
  Expense categories, each mapping to an expense line on Vero's business tax
  return (form 5). The descriptions double as Claude's classification guide.
  """
  use Ash.Type.Enum,
    values: [
      flowers_and_plants:
        "Fresh and dried flowers, plants and greenery bought for resale or arrangements (Vero: Ostot, hankintamenot).",
      florist_supplies:
        "Floral foam, wire, ribbon, wrapping, vases, pots, cards and packaging used in products (Vero: Ostot, hankintamenot).",
      rent: "Rent for the shop, storage or rented equipment (Vero: Vuokrakulut).",
      entertainment:
        "Hospitality for customers and business partners, such as meals, drinks, events and gifts, only 50% deductible (Vero: Edustuskulut).",
      bank_fees:
        "Bank account charges, card terminal and payment provider fees; loan, limit and guarantee fees go in other (Vero: Muut elinkeinotoiminnan kulut).",
      vehicle:
        "Fuel, servicing, tyres, insurance, parking and tolls; only deductible as costs when the car is a business asset, driven over 50% for business (Vero: Muut elinkeinotoiminnan kulut).",
      travel: "Tickets, accommodation and taxis on business trips (Vero: Muut elinkeinotoiminnan kulut).",
      marketing:
        "Advertising, social media ads, printed flyers, signage and ordinary promotional gifts, which are fully deductible (Vero: Muut elinkeinotoiminnan kulut).",
      software: "Software subscriptions, website hosting and domains (Vero: Muut elinkeinotoiminnan kulut).",
      utilities: "Electricity, water, waste, phone and internet (Vero: Muut elinkeinotoiminnan kulut).",
      office_supplies:
        "Stationery, printer ink, cleaning supplies and other consumables (Vero: Muut elinkeinotoiminnan kulut).",
      equipment:
        "Tools, furniture, fridges and other equipment; items up to 1200 € (3600 € a year in total) or lasting 3 years or less are expensed, the rest depreciated (Vero: Muut elinkeinotoiminnan kulut or Poistot).",
      insurance: "Business, liability and property insurance premiums (Vero: Muut elinkeinotoiminnan kulut).",
      professional_services: "Accounting, legal and consultancy fees (Vero: Muut elinkeinotoiminnan kulut).",
      other:
        "Anything that fits none of the other categories, including loan and financing fees (Vero: Muut vähennyskelpoiset kulut or Muut rahoituskulut).",
      unknown:
        "Use when the document does not show what was purchased clearly enough to choose a category. Prefer this over guessing."
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
    defaults [:read]

    destroy :destroy do
      description "Deletes an expense and removes its tags from the Papra document."
      primary? true
      require_atomic? false
      change Edenflowers.Expenses.Changes.RemovePapraTags
    end

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
