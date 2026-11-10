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

  Extracted fields can be corrected in admin. An empty `paid_on` means unpaid,
  so the expense appears on the monthly report's payables sheet. The report
  includes its amounts in the cash expense sheet and attaches its receipt in
  the month it is paid.
  A future `paid_on` records a scheduled bank payment and counts as paid from that day.
  Claude fills `paid_on` when the document shows payment, such as a till receipt.

  Trashing the document in Papra deletes its expense. Restoring or uploading
  the document again allows reimporting.
  """

  use Ash.Resource,
    domain: Edenflowers.Expenses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias Edenflowers.Events
  alias Edenflowers.Expenses.Changes
  alias Edenflowers.Payments.ReferenceNumber

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
      description "The admin Expenses table: ones needing review first, since a paid one goes into the monthly report as Claude read it, then unpaid, soonest due, then newest receipt date."
      pagination offset?: true, keyset?: true, countable: true, required?: false

      prepare build(
                sort: [
                  needs_review: :desc,
                  paid: :asc,
                  due_on: :asc_nils_last,
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
        :reference_number,
        :processed_at
      ]

      accept [
        :document_id,
        :vendor_name,
        :vendor_vat_number,
        :date,
        :paid_on,
        :due_on,
        :reference_number,
        :total_amount,
        :vat_amount,
        :currency,
        :category,
        :description,
        :confidence
      ]

      change set_attribute(:processed_at, &DateTime.utc_now/0)
      change Changes.NormalizeReferenceNumber
      # Re-processing only fills an empty paid date, so Jennie's stays.
      change atomic_update(:paid_on, expr(paid_on || upsert_conflict(:paid_on)))
      change Changes.UpdatePapraDocument
    end

    update :correct do
      description "Jennie checks Claude's extraction, corrects what it got wrong, and can mark it paid today or scheduled in her bank for its due date."

      accept [
        :vendor_name,
        :vendor_vat_number,
        :date,
        :paid_on,
        :due_on,
        :reference_number,
        :total_amount,
        :vat_amount,
        :currency,
        :category,
        :description
      ]

      argument :paid_today, :boolean, default: false

      argument :scheduled_for_due_date, :boolean do
        default false

        description "Jennie has set the invoice up in her bank to be paid on its due date, so that becomes its paid date."
      end

      require_atomic? false
      change set_attribute(:reviewed_at, &DateTime.utc_now/0)

      change fn changeset, _context ->
        if Ash.Changeset.get_argument(changeset, :paid_today) do
          Ash.Changeset.force_change_attribute(changeset, :paid_on, Edenflowers.ShopTime.today())
        else
          changeset
        end
      end

      change fn changeset, _context ->
        if Ash.Changeset.get_argument(changeset, :scheduled_for_due_date) do
          Ash.Changeset.force_change_attribute(changeset, :paid_on, Ash.Changeset.get_attribute(changeset, :due_on))
        else
          changeset
        end
      end

      change Changes.NormalizeReferenceNumber
      change Changes.UpdatePapraDocument
    end

    update :mark_unpaid do
      description "Clears the paid date, for an expense marked paid by mistake. A phone's date picker can't empty the field itself."
      change set_attribute(:paid_on, nil)
    end

    read :awaiting_bank_payment do
      description "The unpaid or scheduled expenses a bank payment with this reference, amount and currency would settle."

      argument :reference_number, :string, allow_nil?: false
      argument :amount, :decimal, allow_nil?: false
      argument :currency, __MODULE__.Currency, allow_nil?: false

      filter expr(
               reference_number == ^arg(:reference_number) and total_amount == ^arg(:amount) and
                 currency == ^arg(:currency) and (is_nil(paid_on) or paid_on > helsinki_today())
             )
    end

    read :unpaid_at do
      description "The expenses Jennie still owed at the end of a day, for the payables list in the accountant's " <>
                    "monthly report: dated by then and not paid by then. A scheduled payment counts as unpaid " <>
                    "until its day, and one paid later still counts, so the list reads the same whenever the " <>
                    "report is built. Undated ones are left out, as they belong to no month. Sorted by date."

      argument :date, :date do
        description "The last day counted, such as the reported month's last day."
        allow_nil? false
      end

      filter expr(date <= ^arg(:date) and (is_nil(paid_on) or paid_on > ^arg(:date)))
      prepare build(sort: [date: :asc, vendor_name: :asc])
    end

    update :paid_from_bank do
      description "The bank booked this expense's payment, so its paid date becomes the booking date, replacing a scheduled one."
      accept []
      argument :booked_on, :date, allow_nil?: false
      change set_attribute(:paid_on, arg(:booked_on))
    end

    action :settle_from_bank, :boolean do
      description "Marks the one expense a booked bank payment settles paid on its booking date. " <>
                    "Matches the reference number, amount and currency exactly; with no match or several, " <>
                    "nothing changes and Jennie marks it by hand. Returns whether one was settled."

      argument :reference_number, :string, allow_nil?: false
      argument :amount, :decimal, allow_nil?: false
      argument :currency, __MODULE__.Currency, allow_nil?: false
      argument :booked_on, :date, allow_nil?: false

      run fn input, context ->
        %{reference_number: reference, amount: amount, currency: currency, booked_on: booked_on} = input.arguments
        opts = Ash.Context.to_opts(context)

        with reference when is_binary(reference) <- ReferenceNumber.normalize(reference),
             {:ok, [expense]} <-
               Edenflowers.Expenses.expenses_awaiting_bank_payment(reference, amount, currency, opts),
             {:ok, _expense} <- Edenflowers.Expenses.mark_expense_paid_from_bank(expense, booked_on, opts) do
          {:ok, true}
        else
          {:error, error} -> {:error, error}
          _no_single_match -> {:ok, false}
        end
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if action(:ingest)
      # The bank sync settles the expenses its payments match.
      authorize_if action([:settle_from_bank, :paid_from_bank])
      # Papra's document:deleted webhook reads and deletes the document's expense.
      authorize_if action_type(:read)
      authorize_if action(:destroy)
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

    publish_all :create, Events.admin_expenses()
    publish_all :update, Events.admin_expenses()
    publish_all :destroy, Events.admin_expenses()

    publish_all :create, Events.admin_expense(:id)
    publish_all :update, Events.admin_expense(:id)
    publish_all :destroy, Events.admin_expense(:id)
  end

  # Claude's draft may lack these, so ingest takes it as it is; Jennie fills
  # them in before she can save or review it. One each, so the form marks each
  # missing field. Marking unpaid doesn't need them.
  validations do
    validate present(:date), where: action_is(:correct)
    validate present(:vendor_name), where: action_is(:correct)
    validate present(:total_amount), where: action_is(:correct)
    validate present(:currency), where: action_is(:correct)

    validate present(:due_on),
      where: [action_is(:correct), argument_equals(:scheduled_for_due_date, true)],
      message: "is needed to schedule the payment"
  end

  attributes do
    uuid_primary_key :id

    attribute :document_id, :string, allow_nil?: false
    attribute :vendor_name, :string
    attribute :vendor_vat_number, :string
    attribute :date, :date

    attribute :paid_on, :date do
      description "The day the money leaves: empty while unpaid, in the future once Jennie has scheduled the payment in her bank. Claude sets it from a document that shows it was already paid."
    end

    attribute :due_on, :date do
      description "When an unpaid invoice falls due, if the document says."
    end

    attribute :reference_number, :string do
      description "The payment reference printed on an invoice, without spaces. The bank sync matches the payment by it."
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
    calculate :matches?,
              :boolean,
              expr(contains(vendor_name, ^arg(:term)) or contains(description, ^arg(:term))) do
      description "The admin expenses search, case-insensitive: whether the term appears in the vendor or description."
      argument :term, :ci_string, allow_nil?: false
    end

    calculate :paid, :boolean, expr(not is_nil(paid_on)) do
      description "Paid or scheduled: Jennie has nothing left to do about the payment."
    end

    calculate :scheduled, :boolean, expr(paid_on > helsinki_today()) do
      description "Scheduled in Jennie's bank for a future day; it counts as paid from then."
    end

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
