defmodule Edenflowers.Expenses.Expense.Category do
  @moduledoc """
  Expense categories, each mapping to an expense line on Vero's business tax
  return, form 5 (Skattedeklaration för näringsverksamhet), named as on the
  Swedish form with its field code. The descriptions double as Claude's
  classification guide.
  """
  use Ash.Type.Enum,
    values: [
      flowers_and_plants:
        "Fresh and dried flowers, plants and greenery bought for resale or arrangements (Vero: 333 Inköp och förändringar av lager).",
      florist_supplies:
        "Floral foam, wire, ribbon, wrapping, vases, pots, cards and packaging used in products (Vero: 333 Inköp och förändringar av lager).",
      rent: "Rent for the shop, storage or rented equipment (Vero: 343 Hyror).",
      entertainment:
        "Hospitality for customers and business partners, such as meals, drinks, events and gifts, only 50% deductible (Vero: 341 Representationskostnader, half in 342 Avdragbar andel av representationskostnader).",
      bank_fees:
        "Bank account charges, card terminal and payment provider fees; loan, limit and guarantee fees go in other (Vero: 344 Övriga avdragbara kostnader).",
      vehicle:
        "Fuel, servicing, tyres, insurance, parking and tolls; only deductible as costs when the car is a business asset, driven over 50% for business (Vero: 344 Övriga avdragbara kostnader).",
      travel: "Tickets, accommodation and taxis on business trips (Vero: 344 Övriga avdragbara kostnader).",
      marketing:
        "Advertising, social media ads, printed flyers, signage and ordinary promotional gifts, which are fully deductible (Vero: 344 Övriga avdragbara kostnader).",
      software: "Software subscriptions, website hosting and domains (Vero: 344 Övriga avdragbara kostnader).",
      utilities: "Electricity, water, waste, phone and internet (Vero: 344 Övriga avdragbara kostnader).",
      office_supplies:
        "Stationery, printer ink, cleaning supplies and other consumables (Vero: 344 Övriga avdragbara kostnader).",
      equipment:
        "Tools, furniture, fridges and other equipment; items up to 1200 € (3600 € a year in total) or lasting 3 years or less are expensed, the rest depreciated (Vero: 344 Övriga avdragbara kostnader, or 338 Avdragbar andel av avskrivningar).",
      insurance: "Business, liability and property insurance premiums (Vero: 344 Övriga avdragbara kostnader).",
      professional_services: "Accounting, legal and consultancy fees (Vero: 344 Övriga avdragbara kostnader).",
      other:
        "Anything that fits none of the other categories, including loan and financing fees (Vero: 344 Övriga avdragbara kostnader, or 349 Övriga finansiella kostnader for financing fees).",
      unknown:
        "Use when the document does not show what was purchased clearly enough to choose a category. Prefer this over guessing."
    ]
end

defmodule Edenflowers.Expenses.Expense.Confidence do
  @moduledoc """
  Confidence levels for fields extracted from an expense receipt.
  """

  use Ash.Type.Enum, values: [:high, :medium, :low]
end

defmodule Edenflowers.Expenses.Expense.Currency do
  @moduledoc """
  Currencies accepted for recorded expenses.
  """

  use Ash.Type.Enum, values: [:eur, :sek]
end

defmodule Edenflowers.Expenses.Expense do
  @moduledoc """
  A receipt or invoice imported from Papra and classified for accounting.

  The extracted fields can be corrected in admin. An empty `paid_on` means it
  is still unpaid, so it stays out of the monthly report until Jennie marks it
  paid. Claude fills `paid_on` when the document shows it was already paid,
  such as a till receipt. Deleting an expense leaves its
  Papra document alone. To import it again, delete the document in Papra and
  upload the PDF again.
  """

  use Ash.Resource,
    domain: Edenflowers.Expenses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias Edenflowers.Expenses.Changes

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
      description "The admin Expenses table: unpaid first, soonest due, then ones needing review, then newest receipt date."
      pagination offset?: true, keyset?: true, countable: true, required?: false

      prepare build(
                sort: [
                  paid: :asc,
                  due_on: :asc_nils_last,
                  needs_review: :desc,
                  date: :desc_nils_first,
                  processed_at: :desc
                ]
              )
    end

    create :ingest do
      description "Upserts an expense record extracted from a receipt/invoice document."
      upsert? true
      upsert_identity :unique_document_id

      upsert_fields [
        :vendor_name,
        :vendor_vat_number,
        :date,
        :due_on,
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
        :paid_on,
        :due_on,
        :total_amount,
        :vat_amount,
        :currency,
        :category,
        :description,
        :confidence
      ]

      change set_attribute(:processed_at, &DateTime.utc_now/0)
      # Re-processing only fills an empty paid date, so Jennie's stays.
      change atomic_update(:paid_on, expr(paid_on || upsert_conflict(:paid_on)))
      change Changes.RenamePapraDocument
    end

    update :correct do
      description "Jennie checks Claude's extraction, corrects what it got wrong, and can mark it paid today."

      accept [
        :vendor_name,
        :vendor_vat_number,
        :date,
        :paid_on,
        :due_on,
        :total_amount,
        :vat_amount,
        :currency,
        :category,
        :description
      ]

      argument :paid_today, :boolean, default: false

      require_atomic? false
      change set_attribute(:reviewed_at, &DateTime.utc_now/0)

      change fn changeset, _context ->
        if Ash.Changeset.get_argument(changeset, :paid_today) do
          Ash.Changeset.force_change_attribute(changeset, :paid_on, Edenflowers.ShopTime.today())
        else
          changeset
        end
      end

      change Changes.RenamePapraDocument
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

  # Expenses arrive in the background from Papra; this refreshes the admin's
  # Expenses page, which has no pull to refresh.
  pub_sub do
    module EdenflowersWeb.Endpoint

    publish_all :create, ["admin", "expenses"]
    publish_all :update, ["admin", "expenses"]
    publish_all :destroy, ["admin", "expenses"]
  end

  # Claude's draft may lack these, so ingest takes it as it is; Jennie fills
  # them in before she can save or review it. One each, so the form marks each
  # missing field.
  validations do
    validate present(:date), on: :update
    validate present(:vendor_name), on: :update
    validate present(:total_amount), on: :update
    validate present(:currency), on: :update
  end

  attributes do
    uuid_primary_key :id

    attribute :document_id, :string, allow_nil?: false
    attribute :vendor_name, :string
    attribute :vendor_vat_number, :string
    attribute :date, :date

    attribute :paid_on, :date do
      description "Empty while unpaid. Claude sets it from a document that shows it was already paid."
    end

    attribute :due_on, :date do
      description "When an unpaid invoice falls due, if the document says."
    end

    attribute :total_amount, :decimal do
      description "The document's total, VAT included, in its `currency`."
      constraints scale: 2
    end

    attribute :vat_amount, :decimal do
      description "The VAT part of `total_amount`, in the same currency."
      constraints scale: 2
    end

    attribute :currency, __MODULE__.Currency
    attribute :category, __MODULE__.Category
    attribute :description, :string
    attribute :confidence, __MODULE__.Confidence, allow_nil?: false
    attribute :processed_at, :utc_datetime, allow_nil?: false
    attribute :reviewed_at, :utc_datetime

    timestamps()
  end

  calculations do
    calculate :paid, :boolean, expr(not is_nil(paid_on))

    calculate :overdue, :boolean, expr(is_nil(paid_on) and due_on < helsinki_today())

    calculate :needs_review,
              :boolean,
              expr(
                is_nil(reviewed_at) and
                  (confidence != :high or is_nil(date) or is_nil(vendor_name) or is_nil(total_amount) or
                     is_nil(currency))
              ) do
      description "Claude was unsure or left a required field empty, and Jennie hasn't saved it since."
    end
  end

  identities do
    identity :unique_document_id, [:document_id]
  end
end
