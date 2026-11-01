defmodule Edenflowers.Payments.Invoice do
  @moduledoc """
  A bill Jennie sends for an order or a Course booking on invoice terms, to
  be paid by bank transfer. A purchase can have several, such as a wedding's
  booking fee and then the rest after delivery.

  Once created it never changes: its number, amount, dates and the buyer
  details it was sent with are frozen, so later edits to the purchase don't
  reach it. A correction is a Credit note, which cancels it while leaving it
  as it was, and a new invoice.

  It is paid once the bank transfers Jennie records against it (Payments
  with its `invoice_id`) cover its amount.

  `:send` emails it to the customer with its PDF; creating one can send it
  at once, and Jennie can send it again while it is open. Sending only stamps
  `sent_at`, so the invoice itself never changes; each send is kept as a
  version for the order log. Sent while `overdue?`, the email is a gentle
  reminder. Nothing sends it automatically.

  Numbers come from one gapless series that continues Zervant's, starting at
  `first_number/0` (see `Changes.IssueInvoice`). The seller details printed
  on it come from `seller/0`.
  """
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

  @doc "The shop's details printed on its invoices: name, business_id, address, iban and bic."
  def seller, do: config()[:seller]

  @doc "The due date an invoice made today gets unless Jennie picks another: 14 days on (Payment.overdue_after_days)."
  def default_due_date, do: Date.add(Edenflowers.ShopTime.today(), Edenflowers.Payments.Payment.overdue_after_days())

  defp config, do: Application.fetch_env!(:edenflowers, :invoices)

  @doc "The order or Course booking a create changeset invoices, loaded with `load`, or nil."
  def purchase(changeset, load) do
    order_id = Ash.Changeset.get_attribute(changeset, :order_id)
    registration_id = Ash.Changeset.get_attribute(changeset, :course_registration_id)

    {resource, id} =
      if order_id,
        do: {Edenflowers.Orders.Order, order_id},
        else: {Edenflowers.Courses.CourseRegistration, registration_id}

    if id, do: Ash.get!(resource, id, load: load, authorize?: false, not_found_error?: false)
  end

  postgres do
    repo Edenflowers.Repo
    table "invoices"
    migration_types amount: :decimal

    check_constraints do
      check_constraint :order_id, "invoices_one_parent",
        check: "(order_id IS NULL) <> (course_registration_id IS NULL)",
        message: "must belong to exactly one order or course registration"
    end

    references do
      reference :order, on_delete: :restrict
      reference :course_registration, on_delete: :restrict
    end
  end

  # Each send, for the order log: sent_at keeps only the latest, and Jennie
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

    read :open_at do
      description "The invoices still owed at the end of a day, for the receivables list in the accountant's " <>
                    "monthly report: made by then, not cancelled by a Credit note dated by then, and not covered " <>
                    "by the Payments dated by then (in Helsinki), refunds and Undos taken off. An invoice paid " <>
                    "or cancelled later still counts, so the list reads the same whenever the report is built. " <>
                    "Sorted by number. Load amount_open_at with the same date for what was owed on each."

      argument :date, :date do
        description "The last day counted, such as the reported month's last day."
        allow_nil? false
      end

      filter expr(
               invoice_date <= ^arg(:date) and
                 not exists(credit_note, credit_date <= ^arg(:date)) and
                 amount_open_at(date: ^arg(:date)) > 0
             )

      prepare build(sort: [number: :asc])
    end

    create :create do
      description "Jennie invoices an order or Course booking on invoice terms whose buyer details are complete " <>
                    "(invoiceable?). It takes the next number in the series and its viitenumero, is dated today " <>
                    "in Helsinki, and freezes a copy of the buyer details. The amount defaults to the Balance not " <>
                    "yet invoiced, the due date to 14 days later (Payment.overdue_after_days) and the language " <>
                    "to the purchase's; Jennie can change all three."

      accept [:order_id, :course_registration_id, :amount, :due_date, :locale]

      argument :email_customer?, :boolean do
        description "Whether to email it to the customer once it is made, as :send does. The admin form starts " <>
                      "with this ticked. A failed email never undoes the invoice: the result's :emailed? " <>
                      "metadata says whether it went, and :send can try again."

        default false
      end

      argument :message, :string do
        description "Jennie's own words for the email, after its first line. Only used when email_customer? is true."
      end

      validate present([:order_id, :course_registration_id], exactly: 1)
      validate Validations.Invoiceable
      change Changes.IssueInvoice
      validate present(:amount), message: "nothing is left to invoice, so enter an amount"
      validate attribute_in(:locale, @locales)
      validate compare(:due_date, greater_than_or_equal_to: :invoice_date), message: "can't be before the invoice date"
      change Changes.SendWhenCreated
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
      authorize_if action(:send)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :number, :integer do
      description "The invoice number, from one gapless series shared with credit notes that continues Zervant's."
      allow_nil? false
    end

    attribute :reference_number, :string do
      description "The viitenumero the customer pays with: the number followed by its Finnish 7-3-1 check digit, " <>
                    "as unspaced digits. ReferenceNumber.format/1 groups it for printing."

      allow_nil? false
    end

    attribute :invoice_date, :date do
      description "The day it was made, in Helsinki."
      allow_nil? false
    end

    attribute :due_date, :date do
      description "When it is to be paid: 14 days after the invoice date unless Jennie chose another day."
      allow_nil? false
    end

    attribute :amount, :decimal do
      description "Due on this invoice in euros, VAT included: the Balance not yet invoiced unless Jennie chose " <>
                    "another amount."

      allow_nil? false
      constraints greater_than: 0, scale: 2
    end

    attribute :locale, :string do
      description "The language it is written in: the purchase's unless Jennie chose another."
      allow_nil? false
    end

    attribute :buyer_name, :string do
      description "The customer's name, as it was when invoiced."
      allow_nil? false
    end

    attribute :buyer_email, :string do
      description "Where it is sent: the customer's email when invoiced."
      allow_nil? false
    end

    attribute :buyer_address, :string do
      description "The customer's own postal address when invoiced, if the purchase has one: a delivery to " <>
                    "themselves, not a gift's Recipient. Nil otherwise."
    end

    attribute :business_customer, :boolean do
      description "Whether it was addressed to a company, with the company details below."
      allow_nil? false
      default false
    end

    attribute :company_name, :string do
      description "The buying company's name when invoiced. Nil for a consumer."
    end

    attribute :business_id, :string do
      description "The buying company's Y-tunnus when invoiced. Nil for a consumer."
    end

    attribute :billing_address, :string do
      description "Where the company was billed when invoiced, one line per row. Nil for a consumer."
    end

    attribute :customer_reference, :string do
      description "The company's own reference (viitteenne), such as a PO number, when invoiced. Optional."
    end

    attribute :sent_at, :utc_datetime do
      description "When it was last emailed to the customer. Nil until it has been: Jennie may make one without " <>
                    "sending it, or its email may have failed."
    end

    timestamps()
  end

  relationships do
    belongs_to :order, Edenflowers.Orders.Order do
      description "The order it bills. Nil when it bills a Course booking: it belongs to exactly one."
    end

    belongs_to :course_registration, Edenflowers.Courses.CourseRegistration do
      description "The Course booking it bills. Nil when it bills an order: it belongs to exactly one."
    end

    has_many :payments, Edenflowers.Payments.Payment do
      description "The bank transfers Jennie recorded as paying it, and any Undo or refund of them."
    end

    has_one :credit_note, Edenflowers.Payments.CreditNote do
      description "The Credit note that cancels it, if Jennie cancelled it."
    end
  end

  calculations do
    calculate :status,
              :atom,
              expr(
                cond do
                  exists(credit_note, true) -> :cancelled
                  amount_paid >= amount -> :paid
                  true -> :open
                end
              ) do
      constraints one_of: [:open, :paid, :cancelled]

      description "Where it stands: :cancelled once a Credit note names it, otherwise :open until its Payments " <>
                    "cover its amount, then :paid. A refund or Undo of one of them can open it again. Only " <>
                    ":open counts toward what a purchase has invoiced and can take a Payment."
    end

    calculate :cancellable?, :boolean, expr(status == :open and amount_paid == 0) do
      description "Whether Jennie can cancel it with a Credit note: open with nothing paid on it. One with " <>
                    "Payments, even part-paid, can't be, as those Payments would count against no open invoice; " <>
                    "she undoes them first. Validations.Cancellable refuses a Credit note otherwise."
    end

    calculate :overdue?, :boolean, expr(status == :open and due_date < helsinki_today()) do
      description "Whether it is late: still open after its due date, counted in Helsinki days, so it turns " <>
                    "overdue the day after the due date. A paid or cancelled invoice is never overdue; one " <>
                    "paid only in part still is. Admin flags it, the Overview lists its purchase under Payment " <>
                    "overdue, and sending it again makes the email a friendly reminder. Nothing is sent " <>
                    "automatically: Jennie decides whether to nudge."
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

    calculate :purchase_reference, :string, expr(order.order_reference || course_registration.reference) do
      description "The reference of the order or Course booking it bills."
    end

    calculate :amount_unpaid, :decimal, expr(amount - amount_paid) do
      description "What is still to pay on it in euros: its amount less its Payments. Negative if it was overpaid."
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
