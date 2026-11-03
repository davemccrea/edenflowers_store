defmodule Edenflowers.Payments.CreditNote do
  @moduledoc """
  What cancels an Invoice (hyvityslasku, kreditnota): Jennie makes one to
  put a mistake right, then sends a new invoice if anything is still to pay.

  It takes the next number in the series it shares with Invoices
  (`NumberSeries`), names the Invoice it cancels and credits its whole
  amount. Its buyer, language and amount are that Invoice's, which never
  changes, so they are read from it rather than copied.

  The Invoice itself stays as it was; it reads as `:cancelled` once a credit
  note names it, which takes it out of the open invoices and the amount
  already invoiced. Only an Invoice with nothing paid on it can be cancelled
  (`Invoice.cancellable?`).

  `:send` emails it to the customer with its PDF, like an Invoice.
  """
  use Ash.Resource,
    domain: Edenflowers.Payments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshPaperTrail.Resource]

  alias Edenflowers.Payments.Changes
  alias Edenflowers.Payments.Validations

  postgres do
    repo Edenflowers.Repo
    table "credit_notes"

    references do
      reference :invoice, on_delete: :restrict
    end
  end

  paper_trail do
    change_tracking_mode :changes_only
    store_action_name? true
    ignore_attributes [:inserted_at, :updated_at]
    ignore_actions [:create]
    on_actions [:send]
    only_when_changed? false
    metadata :email_message, :string
  end

  actions do
    defaults [:read]

    create :create do
      description "Jennie cancels an Invoice that has nothing paid on it (Invoice.cancellable?) by issuing a " <>
                    "credit note for its whole amount. It takes the next number in the series Invoices share, is " <>
                    "dated today in Helsinki, and can carry her reason, printed on it. The Invoice stops counting " <>
                    "as open. Paid and partly paid invoice corrections go to the accountant."

      accept [:invoice_id, :reason]

      argument :email_customer?, :boolean do
        description "Whether to email it to the customer once it is made, as :send does. The admin form starts " <>
                      "with this ticked when the Invoice was sent. A failed email never undoes the credit note: " <>
                      "the result's :emailed? metadata says whether it went, and :send can try again."

        default false
      end

      argument :message, :string do
        description "Jennie's own words for the email, after its first line. Only used when email_customer? is true."
      end

      validate Validations.Cancellable, before_action?: true
      change Changes.IssueCreditNote
      change Changes.SendWhenCreated
    end

    update :send do
      description "Jennie emails the credit note to the buyer of the Invoice it cancels, in that Invoice's " <>
                    "language, with its PDF attached and her optional message, and sent_at is stamped. Nothing " <>
                    "else changes. Sent by hand only, and it can be sent again."

      accept []

      argument :message, :string do
        description "Jennie's own words for the email, after its first line."
      end

      transaction? false
      require_atomic? false
      change Changes.SendCreditNote
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
      description "The credit note's own number, from the gapless series it shares with Invoices."
      allow_nil? false
    end

    attribute :credit_date, :date do
      description "The day it was made, in Helsinki: from then on the Invoice it names is cancelled."
      allow_nil? false
    end

    attribute :reason, :string do
      description "Why Jennie cancelled the Invoice, in its language, printed on the credit note. Optional."
    end

    attribute :pdf, :binary do
      description "The PDF as made, rendered once when it is created and kept for the books: every download " <>
                    "and email sends these bytes. Not selected by default; load it."

      allow_nil? false
      select_by_default? false
    end

    attribute :sent_at, :utc_datetime do
      description "When it was last emailed to the customer. Nil until it has been: Jennie may not email one " <>
                    "for an Invoice that never went out, or its email may have failed."
    end

    timestamps()
  end

  relationships do
    belongs_to :invoice, Edenflowers.Payments.Invoice do
      description "The Invoice it cancels and credits in full. Each Invoice has at most one."
      allow_nil? false
    end
  end

  identities do
    identity :unique_number, [:number]

    identity :one_per_invoice, [:invoice_id] do
      message "is already cancelled"
    end
  end
end
