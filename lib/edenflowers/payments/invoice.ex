defmodule Edenflowers.Payments.Invoice do
  @moduledoc "Standalone editable drafts, numbered and frozen when issued."
  use Ash.Resource,
    domain: Edenflowers.Payments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshPaperTrail.Resource]

  alias Edenflowers.Payments.Changes
  alias Edenflowers.Payments.Validations

  @locales Edenflowers.Locales.all()

  @doc "The number the first shop invoice gets, when there is none yet: Zervant's last number + 1."
  def first_number, do: config()[:first_number]

  @doc "The seller a new invoice freezes and prints: name, business_id, address and iban (`config :edenflowers, :seller`)."
  def seller, do: Application.fetch_env!(:edenflowers, :seller)

  @doc "The yearly late payment interest a new invoice states, as a fraction: 0.08 for 8 %."
  def late_interest_rate, do: Decimal.new(config()[:late_interest_rate])

  @doc "The due date an invoice made today gets unless Jennie picks another: 14 days on (Payment.overdue_after_days)."
  def default_due_date, do: Date.add(Edenflowers.ShopTime.today(), Edenflowers.Payments.Payment.overdue_after_days())

  defp config, do: Application.fetch_env!(:edenflowers, :invoices)

  @doc """
  The invoice with `id`, its row locked until the transaction ends, then
  loaded with `load` read after the lock, or nil. Cancelling it and paying it
  both take the lock, so neither can commit on a status the other has just
  changed: a Credit note never lands on money, nor money on a Credit note.
  """
  def get_locked(id, load) do
    require Ash.Query

    __MODULE__
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
    |> then(&(&1 && Ash.load!(&1, load, authorize?: false)))
  end

  postgres do
    repo Edenflowers.Repo
    table "invoices"
    migration_types amount: :decimal
  end

  # Each send, for the invoice history: sent_at keeps only the latest, and Jennie
  # needs to see when a reminder went out after the first email.
  paper_trail do
    change_tracking_mode :changes_only
    store_action_name? true
    ignore_attributes [:inserted_at, :updated_at]
    # Creating one is logged from the invoice itself; only sends are versioned.
    ignore_actions [:create]
    on_actions [:send]
    # sent_at is to the second, so a resend within the same second changes nothing but still went out.
    only_when_changed? false

    # Jennie's message in the email, and whether it went as an overdue reminder.
    metadata :email_message, :string
    metadata :reminder, :boolean
  end

  actions do
    defaults [:read]

    read :admin_list do
      pagination offset?: true, keyset?: true, countable: true, required?: false
      prepare build(sort: [inserted_at: :desc])
    end

    read :previous_customers do
      description "Find previous invoice customers, using the latest emailed invoice for each email and business."
      argument :term, :ci_string, allow_nil?: false

      filter expr(
               not is_nil(sent_at) and
                 (contains(buyer_name, ^arg(:term)) or contains(buyer_email, ^arg(:term)) or
                    contains(company_name, ^arg(:term)))
             )

      prepare build(
                distinct: [:buyer_email_key, :business_customer, :business_id],
                distinct_sort: [sent_at: :desc, inserted_at: :desc, id: :desc],
                sort: [sent_at: :desc, inserted_at: :desc, id: :desc],
                load: [:buyer]
              )
    end

    read :open_at do
      description "The invoices still owed at the end of a day, for the receivables list in the accountant's " <>
                    "monthly report: issued by then (in Helsinki) and dated by then, not cancelled by a Credit note dated by then, and not covered " <>
                    "by the Payments dated by then (in Helsinki), refunds and Undos taken off. An invoice paid " <>
                    "or cancelled later still counts, so the list reads the same whenever the report is built. " <>
                    "Sorted by number. Load amount_open_at with the same date for what was owed on each."

      argument :date, :date do
        description "The last day counted, such as the reported month's last day."
        allow_nil? false
      end

      filter expr(
               not is_nil(issued_at) and
                 fragment("(? AT TIME ZONE 'UTC' AT TIME ZONE ?)::date", issued_at, ^Edenflowers.ShopTime.timezone()) <=
                   ^arg(:date) and
                 invoice_date <= ^arg(:date) and
                 not exists(credit_note, credit_date <= ^arg(:date)) and
                 amount_open_at(date: ^arg(:date)) > 0
             )

      prepare build(sort: [number: :asc])
    end

    create :create do
      description "Create an unnumbered standalone invoice draft."

      accept [
        :buyer_name,
        :buyer_email,
        :buyer_address,
        :business_customer,
        :company_name,
        :business_id,
        :billing_address,
        :customer_reference,
        :invoice_date,
        :due_date,
        :locale,
        :lines,
        :supply_date,
        :supply_description
      ]
    end

    update :update_draft do
      accept [
        :buyer_name,
        :buyer_email,
        :buyer_address,
        :business_customer,
        :company_name,
        :business_id,
        :billing_address,
        :customer_reference,
        :invoice_date,
        :due_date,
        :locale,
        :lines,
        :supply_date,
        :supply_description
      ]

      require_atomic? false
      change Changes.EditInvoiceDraft
    end

    update :issue do
      accept []
      require_atomic? false
      change Changes.IssueInvoice
      change Changes.FreezeInvoiceContent
    end

    update :record_payment do
      description "Records a bank transfer received for this issued invoice, without sending an email."
      accept []
      argument :amount, :decimal, allow_nil?: false, constraints: [greater_than: 0, scale: 2]
      argument :paid_at, :utc_datetime, allow_nil?: false, default: &DateTime.utc_now/0
      require_atomic? false
      change Changes.RecordInvoicePayment
    end

    update :undo_payment do
      description "Reverses a bank transfer entered by mistake, keeping its original ledger row."
      accept []
      argument :payment_id, :uuid, allow_nil?: false
      argument :paid_at, :utc_datetime, allow_nil?: false, default: &DateTime.utc_now/0
      require_atomic? false
      change {Changes.RecordInvoicePayment, reversal?: true}
    end

    update :send do
      description "Jennie emails the invoice to its buyer's email, in its own language, with its PDF attached and " <>
                    "her optional message, and sent_at is stamped. Nothing else about the invoice changes. Sent " <>
                    "by hand only, and only while it is open (sendable?), as often as she likes. Sent while it " <>
                    "is overdue?, the email becomes a friendly reminder with a gentler subject and the same PDF. " <>
                    "Each send is recorded as a version, with her message and whether it was a reminder."

      accept []

      argument :message, :string do
        description "Jennie's own words for the email, after its first line."
      end

      transaction? false
      require_atomic? false
      validate Validations.Sendable
      change Changes.SendInvoice
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if action_type(:read)
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if action_type([:read, :create])
      authorize_if action([:send, :update_draft, :issue, :record_payment, :undo_payment])
    end
  end

  validations do
    validate attribute_in(:locale, @locales)
  end

  attributes do
    uuid_primary_key :id

    attribute :number, :integer do
      description "The invoice number, from one gapless series shared with credit notes that continues Zervant's."
    end

    attribute :reference_number, :string do
      description "The viitenumero the customer pays with: the number followed by its Finnish 7-3-1 check digit, " <>
                    "as unspaced digits. ReferenceNumber.format/1 groups it for printing."
    end

    attribute :invoice_date, :date do
      description "The invoice date chosen in the draft."
      default &Edenflowers.ShopTime.today/0
      allow_nil? false
    end

    attribute :due_date, :date do
      description "The payment due date."
      default &__MODULE__.default_due_date/0
      allow_nil? false
    end

    attribute :amount, :decimal do
      description "Due on this invoice in euros, VAT included: the gross total of its lines, set when it is " <>
                    "issued. 0 on a draft."

      default 0
      constraints min: 0, scale: 2
    end

    attribute :locale, :string do
      description "The document language."
      default "fi"
      allow_nil? false
    end

    attribute :buyer_name, :string do
      description "The customer's name, as it was when invoiced."
    end

    attribute :buyer_email, Edenflowers.Types.Email do
      description "Where it is sent: the customer's email when invoiced."
    end

    attribute :buyer_address, :string do
      description "The consumer's postal address, printed under their name. A business customer is billed at " <>
                    "billing_address instead."
    end

    attribute :business_customer, :boolean do
      description "Whether it was addressed to a company, with the company details below."
      allow_nil? false
      default false
    end

    attribute :company_name, :string do
      description "The buying company's name when invoiced. Nil for a consumer."
    end

    attribute :business_id, Edenflowers.Types.BusinessId do
      description "The buying company's Y-tunnus when invoiced. Nil for a consumer."
    end

    attribute :billing_address, :string do
      description "Where the company was billed when invoiced, one line per row. Nil for a consumer."
    end

    attribute :customer_reference, :string do
      description "The company's own reference (viitteenne), such as a PO number, when invoiced. Optional."
    end

    attribute :content, :map do
      description "Everything its PDF prints but the labels, frozen on issuance from its own billed lines, " <>
                    "numeric VAT snapshot, seller/buyer, dates, number, amount and bank details. Every download " <>
                    "and resend uses these immutable formatted string keys."
    end

    attribute :issued_at, :utc_datetime_usec
    attribute :supply_date, :date
    attribute :supply_description, :string

    attribute :lines, {:array, Edenflowers.Payments.InvoiceLine} do
      description "What it bills. A draft's may be unfinished; issuing needs them complete and freezes them " <>
                    "into financial_snapshot."

      allow_nil? false
      default []
    end

    attribute :financial_snapshot, :map
    attribute :seller_snapshot, :map

    attribute :sent_at, :utc_datetime do
      description "When it was last emailed to the customer. Nil until it has been: Jennie may make one without " <>
                    "sending it, or its email may have failed."
    end

    timestamps()
  end

  relationships do
    has_many :payments, Edenflowers.Payments.Payment do
      description "The bank transfers Jennie recorded as paying it, and any Undo or refund of them."
    end

    has_one :credit_note, Edenflowers.Payments.CreditNote do
      description "The Credit note that cancels it, if Jennie cancelled it."
    end
  end

  calculations do
    calculate :buyer_email_key, :string, expr(string_downcase(buyer_email))

    calculate :editable?, :boolean, expr(is_nil(issued_at))
    calculate :issued?, :boolean, expr(not is_nil(issued_at))

    calculate :status,
              :atom,
              expr(
                cond do
                  is_nil(issued_at) -> :draft
                  exists(credit_note, true) -> :cancelled
                  amount_paid >= amount -> :paid
                  true -> :open
                end
              ) do
      constraints one_of: [:draft, :open, :paid, :cancelled]

      description "Where it stands: :cancelled once a Credit note names it, otherwise :open until its Payments " <>
                    "cover its amount, then :paid. An Undo of one of them can open it again. Only an :open " <>
                    "invoice can take a Payment, and never more than its amount_unpaid."
    end

    calculate :cancellable?, :boolean, expr(status == :open and amount_paid == 0) do
      description "Whether Jennie can cancel it with a Credit note: open with nothing paid on it. One with " <>
                    "Payments, even part-paid, can't be, as those Payments would count against no open invoice; " <>
                    "she consults the accountant for corrections. Validations.Cancellable refuses a Credit note otherwise."
    end

    calculate :overdue?, :boolean, expr(status == :open and due_date < helsinki_today()) do
      description "Whether it is late: still open after its due date, counted in Helsinki days, so it turns " <>
                    "overdue the day after the due date. A paid or cancelled invoice is never overdue; one " <>
                    "paid only in part still is. Admin flags it, and sending it again makes the email a friendly " <>
                    "reminder. Nothing is sent automatically: Jennie decides whether to nudge."
    end

    calculate :sendable?, :boolean, expr(status == :open) do
      description "Whether Jennie can email it, for the first time or again: only while it is open. A paid " <>
                    "invoice needs no email and a cancelled one has its Credit note instead. " <>
                    "Validations.Sendable refuses :send otherwise."
    end

    calculate :paid?, :boolean, expr(status == :paid) do
      description "Whether its Payments cover its amount."
    end

    calculate :amount_open_at,
              :decimal,
              expr(
                amount -
                  (sum(payments,
                     field: :amount,
                     query: [
                       filter:
                         expr(
                           fragment(
                             "(? AT TIME ZONE 'UTC' AT TIME ZONE ?)::date",
                             paid_at,
                             ^Edenflowers.ShopTime.timezone()
                           ) <=
                             ^arg(:date)
                         )
                     ]
                   ) || 0)
              ) do
      description "What was still to pay on it at the end of a day in euros: its amount less its Payments dated " <>
                    "that day or before in Helsinki, refunds and Undos taken off. Later Payments don't count, so " <>
                    "the monthly report shows what was owed at month end. Ignores Credit notes: open_at leaves " <>
                    "cancelled invoices out."

      argument :date, :date, allow_nil?: false
    end

    calculate :buyer, :string, expr(if business_customer, do: company_name, else: buyer_name) do
      description "Who it bills, for lists: the company's name for a business customer, otherwise the customer's."
    end

    calculate :amount_unpaid, :decimal, expr(amount - amount_paid) do
      description "What is still to pay on it in euros: its amount less its Payments, which can't exceed it."
    end
  end

  aggregates do
    sum :amount_paid, :payments, :amount do
      description "What has been paid on it in euros: the Payments recorded against it, refunds and Undos " <>
                    "taken off."

      default Decimal.new("0")
    end
  end

  identities do
    identity :unique_number, [:number]
  end
end
