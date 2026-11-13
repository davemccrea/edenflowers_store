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

  require Ash.Query

  alias Edenflowers.Events
  alias Edenflowers.Expenses.Calculations
  alias Edenflowers.Expenses.Changes

  attributes do
    uuid_primary_key :id

    attribute :document_id, :string do
      description "The id of its receipt or invoice in Papra. One expense per document: re-processing the " <>
                    "document updates this expense."

      allow_nil? false
    end

    attribute :vendor_name, :string
    attribute :vendor_vat_number, :string

    attribute :date, :date do
      description "The date printed on the receipt or invoice, which is also its document date in Papra. Not " <>
                    "when it was paid: that is paid_on."
    end

    attribute :paid_on, :date do
      description "The day the money leaves: empty while unpaid, in the future once Jennie has scheduled the payment in her bank. Claude sets it from a document that shows it was already paid."
    end

    attribute :due_on, :date do
      description "When an unpaid invoice falls due, if the document says."
    end

    attribute :reference_number, :string do
      description "The payment reference printed on an invoice, without spaces. The bank sync matches the payment by it."
    end

    attribute :bank_transaction_id, :string do
      description "The bank's id for the payment that paid it: the one the bank sync settled it with, a card " <>
                    "payment linked by amount and date, or one Jennie linked by hand. So a payment quoting no " <>
                    "reference settles one expense only. Moved to unlinked_bank_transaction_ids when Jennie marks it " <>
                    "unpaid or unlinks it, so a wrong match isn't repeated."
    end

    attribute :unlinked_bank_transaction_ids, {:array, :string} do
      description "Bank ids of payments Jennie unlinked from it, which must never link to it again by themselves."
      allow_nil? false
      default []
    end

    attribute :matched_by_amount, :boolean do
      allow_nil? false
      default false

      description "The bank sync marked it paid from a payment quoting no reference, going by the amount alone, " <>
                    "and Jennie hasn't saved or unmarked it since. Her page says so, as the match can be wrong."
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

    attribute :category, __MODULE__.Category do
      description "The expense line on Vero's business tax return it belongs to. :unknown when the document " <>
                    "doesn't show what was bought."
    end

    attribute :description, :string do
      description "A short note of what was bought, in Finland Swedish, as Claude wrote it or Jennie corrected it."
    end

    attribute :sure, :boolean do
      description "Whether Claude was sure of the extraction as a whole. When it wasn't, Jennie reviews it."
      allow_nil? false
    end

    attribute :uncertainty, :string do
      description "What Claude was unsure of when it wasn't sure, in Finland Swedish, so Jennie knows " <>
                    "what to check. Nil for expenses read before Claude was asked."
    end

    attribute :processed_at, :utc_datetime do
      description "When Claude last extracted it from its document."
      allow_nil? false
    end

    attribute :reviewed_at, :utc_datetime do
      description "When Jennie last saved it with :correct, which settles needs_review. Nil while it is as Claude read it."
    end

    timestamps()
  end

  relationships do
    has_one :bank_transaction, Edenflowers.Bank.Transaction do
      description "The stored bank payment that paid it. None for payments booked before the sync kept them."
      source_attribute :bank_transaction_id
      destination_attribute :bank_id
    end
  end

  calculations do
    calculate :amount_distance,
              :decimal,
              expr(
                if total_amount >= ^arg(:amount) do
                  total_amount - ^arg(:amount)
                else
                  ^arg(:amount) - total_amount
                end
              ) do
      description "How far its total is from a payment's amount, to offer the closest receipts first."
      argument :amount, :decimal, allow_nil?: false
    end

    calculate :same_amount?,
              :boolean,
              expr(total_amount == ^arg(:amount) and currency == ^arg(:currency)) do
      description "Whether its total is exactly a payment's amount, in the payment's currency. A nil currency, " <>
                    "for one expenses can't be in, matches none."

      argument :amount, :decimal, allow_nil?: false
      argument :currency, __MODULE__.Currency
    end

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

    calculate :overdue, :boolean, expr(is_nil(paid_on) and due_on < helsinki_today()) do
      description "Unpaid and unscheduled after its due date, counted in Helsinki days. Never for one with no due date."
    end

    calculate :needs_review,
              :boolean,
              expr(
                matched_by_amount or
                  (is_nil(reviewed_at) and
                     (not sure or is_nil(date) or is_nil(vendor_name) or is_nil(total_amount) or
                        is_nil(currency)))
              ) do
      description "Claude was unsure or left a required field empty, or the bank sync marked it paid by amount " <>
                    "alone, and Jennie hasn't saved it since. review_reasons says which."
    end

    calculate :review_reasons, {:array, :atom}, Calculations.ReviewReasons do
      description "Why it needs review, for Jennie's page: empty when needs_review is false."
    end
  end

  identities do
    identity :unique_document_id, [:document_id]
  end

  actions do
    defaults [:read, :destroy]

    read :admin_list do
      description "The admin Expenses table, newest document date first. Undated ones lead, since Jennie has to date them."
      pagination offset?: true, keyset?: true, countable: true, required?: false

      prepare build(sort: [date: :desc_nils_first, processed_at: :desc])
    end

    action :paid_totals, {:array, :map} do
      description "The totals of expenses paid between two dates, inclusive, one per currency, euros first: " <>
                    "what the monthly report's expense sheet sums for a month. One with no currency is left out until " <>
                    "Jennie fills it in, since its review asks her to."

      argument :from, :date, allow_nil?: false
      argument :to, :date, allow_nil?: false

      run fn input, context ->
        %{from: from, to: to} = input.arguments

        with {:ok, expenses} <-
               __MODULE__
               |> Ash.Query.filter(
                 paid_on >= ^from and paid_on <= ^to and not is_nil(total_amount) and not is_nil(currency)
               )
               |> Ash.read(Ash.Context.to_opts(context)) do
          {:ok,
           expenses
           |> Enum.group_by(& &1.currency, & &1.total_amount)
           |> Enum.sort_by(fn {currency, _} -> currency != :eur end)
           |> Enum.map(fn {currency, amounts} ->
             %{currency: currency, total: Enum.reduce(amounts, Decimal.new("0.00"), &Decimal.add/2)}
           end)}
        end
      end
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
        :sure,
        :uncertainty,
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
        :sure,
        :uncertainty
      ]

      change set_attribute(:processed_at, &DateTime.utc_now/0)
      change Changes.NormalizeReferenceNumber
      # Re-processing only fills an empty paid date, so Jennie's stays.
      change atomic_update(:paid_on, expr(paid_on || upsert_conflict(:paid_on)))
      change Changes.UpdatePapraDocument
      change Changes.MatchBankPayments
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

      argument :paid_today, :boolean do
        default false
        description "Jennie paid it today, so today in Helsinki becomes its paid date, whatever paid_on says."
      end

      argument :scheduled_for_due_date, :boolean do
        default false

        description "Jennie has set the invoice up in her bank to be paid on its due date, so that becomes its paid date."
      end

      require_atomic? false
      change set_attribute(:reviewed_at, &DateTime.utc_now/0)
      change set_attribute(:matched_by_amount, false)

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
      description "Clears the paid date, for an expense marked paid by mistake. A phone's date picker can't empty the " <>
                    "field itself. A bank payment that marked it paid wasn't its payment, so it's unlinked."

      require_atomic? false
      change set_attribute(:paid_on, nil)
      change Changes.ForgetBankPayment
    end

    read :awaiting_bank_payment do
      description "The unpaid or scheduled expenses a bank payment with this reference, amount and currency would settle."

      argument :reference_number, :string,
        allow_nil?: false,
        description: "The reference the payment quotes, as unspaced digits."

      argument :amount, :decimal, allow_nil?: false, description: "The payment's amount, which must equal total_amount."
      argument :currency, __MODULE__.Currency, allow_nil?: false

      filter expr(
               reference_number == ^arg(:reference_number) and total_amount == ^arg(:amount) and
                 currency == ^arg(:currency) and (is_nil(paid_on) or paid_on > helsinki_today())
             )
    end

    read :awaiting_unreferenced_bank_payment do
      description "The unpaid or scheduled expenses a bank payment quoting no reference could settle: the same " <>
                    "amount and currency, dated in the 60 days up to the day it was booked. Undated ones are " <>
                    "left out, and so are older ones: a payment today rarely pays those, and Jennie marks them."

      argument :amount, :decimal, allow_nil?: false, description: "The payment's amount, which must equal total_amount."
      argument :currency, __MODULE__.Currency, allow_nil?: false
      argument :booked_on, :date, allow_nil?: false, description: "The day the bank booked the payment."

      filter expr(
               total_amount == ^arg(:amount) and currency == ^arg(:currency) and date <= ^arg(:booked_on) and
                 date >= date_add(^arg(:booked_on), -60, :day) and (is_nil(paid_on) or paid_on > helsinki_today())
             )
    end

    read :paid_without_bank_payment do
      description "The expenses of this amount and currency marked paid in the week up to a booking, by a receipt " <>
                    "or by Jennie, not by the bank sync. A payment quoting no reference is probably one of " <>
                    "theirs reaching the bank, so it must not settle another expense."

      argument :amount, :decimal, allow_nil?: false, description: "The payment's amount, which must equal total_amount."
      argument :currency, __MODULE__.Currency, allow_nil?: false
      argument :booked_on, :date, allow_nil?: false, description: "The day the bank booked the payment."

      filter expr(
               total_amount == ^arg(:amount) and currency == ^arg(:currency) and is_nil(bank_transaction_id) and
                 paid_on <= ^arg(:booked_on) and paid_on >= date_add(^arg(:booked_on), -7, :day)
             )
    end

    read :paid_near_bank_payment do
      description "Expenses a payment out could be the receipt for, though it settles none: paid by other " <>
                    "means within a week of the booking, as a card receipt is (a scheduled one isn't paid yet), " <>
                    "with the same amount and currency, not linked to any payment, and not unlinked from this " <>
                    "one. Earliest paid first."

      argument :bank_transaction_id, :string, allow_nil?: false
      argument :amount, :decimal, allow_nil?: false, description: "The payment's amount, which must equal total_amount."
      argument :currency, __MODULE__.Currency, allow_nil?: false
      argument :booked_on, :date, allow_nil?: false, description: "The day the bank booked the payment."

      filter expr(
               total_amount == ^arg(:amount) and currency == ^arg(:currency) and is_nil(bank_transaction_id) and
                 paid_on >= date_add(^arg(:booked_on), -7, :day) and paid_on <= date_add(^arg(:booked_on), 7, :day) and
                 paid_on <= helsinki_today() and
                 not fragment("? = ANY(?)", ^arg(:bank_transaction_id), unlinked_bank_transaction_ids)
             )

      prepare build(sort: [paid_on: :asc])
    end

    read :linkable_by_hand do
      description "The expenses Jennie can pick for a payment missing its receipt: not linked to a payment and " <>
                    "dated within 30 days of the booking, closest amount first. Any currency, as a card payment " <>
                    "abroad books in euros. Each says whether it is exactly the payment's amount and whether it is paid."

      argument :booked_on, :date, allow_nil?: false
      argument :amount, :decimal, allow_nil?: false
      argument :currency, :string, allow_nil?: false, description: "The payment's currency, as the bank sent it."

      filter expr(
               is_nil(bank_transaction_id) and date >= date_add(^arg(:booked_on), -30, :day) and
                 date <= date_add(^arg(:booked_on), 30, :day)
             )

      prepare fn query, _context ->
        amount = Ash.Query.get_argument(query, :amount)
        currency = Ash.Query.get_argument(query, :currency)
        currency = if __MODULE__.Currency.match?(currency), do: currency

        query
        |> Ash.Query.sort(amount_distance: {%{amount: amount}, :asc_nils_last}, date: :desc)
        |> Ash.Query.load([:overdue, :scheduled, same_amount?: %{amount: amount, currency: currency}])
      end
    end

    update :link_bank_payment do
      description "This bank payment paid it. An unpaid or scheduled expense becomes paid on the booking date; " <>
                    "one already paid keeps its date."

      accept []
      argument :booked_on, :date, allow_nil?: false, description: "The day the bank booked the payment."
      argument :bank_transaction_id, :string, allow_nil?: false

      # Another payment may have linked it since Jennie's picker loaded.
      change filter(expr(is_nil(bank_transaction_id)))
      change set_attribute(:bank_transaction_id, arg(:bank_transaction_id))
      change set_attribute(:matched_by_amount, false)

      change atomic_update(
               :paid_on,
               expr(if is_nil(paid_on) or paid_on > helsinki_today(), do: ^arg(:booked_on), else: paid_on)
             )
    end

    update :unlink_bank_payment do
      description "Jennie says the linked bank payment didn't pay it. The payment goes back to missing a receipt " <>
                    "and never links to this expense by itself again. The paid date stays."

      accept []
      require_atomic? false
      change Changes.ForgetBankPayment
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
      argument :booked_on, :date, allow_nil?: false, description: "The day the bank booked the payment."
      argument :bank_transaction_id, :string, description: "The bank's id for the payment, if it gave one."

      argument :matched_by_amount, :boolean,
        default: false,
        description: "The payment quoted no reference, so only its amount says it pays this expense."

      change set_attribute(:paid_on, arg(:booked_on))
      change set_attribute(:bank_transaction_id, arg(:bank_transaction_id))
      change set_attribute(:matched_by_amount, arg(:matched_by_amount))
    end

    action :settle_from_bank, :boolean do
      description "Marks the one expense a booked bank payment settles paid on its booking date. " <>
                    "A payment quoting a reference must match it, the amount and the currency exactly. " <>
                    "One quoting none settles the only expense of its amount and currency dated in the 60 days " <>
                    "up to the booking, unless it has settled one already or one of that amount was marked " <>
                    "paid by hand that week. With no match or several, " <>
                    "nothing changes and Jennie marks it by hand. Returns whether one was settled."

      argument :reference_number, :string, description: "The reference the payment quotes, spaced or not, if any."

      argument :amount, :decimal,
        allow_nil?: false,
        description: "What left the account, as a positive amount in `currency`."

      argument :currency, __MODULE__.Currency, allow_nil?: false
      argument :booked_on, :date, allow_nil?: false, description: "The day the bank booked the payment."

      argument :bank_transaction_id, :string, allow_nil?: false, description: "The bank's id for the payment."

      run Edenflowers.Expenses.Actions.SettleExpenseFromBank
    end
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

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if action(:ingest)
      # The bank sync settles the expenses its payments match.
      authorize_if action([:settle_from_bank, :paid_from_bank, :link_bank_payment])
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
end
