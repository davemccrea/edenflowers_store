defmodule Edenflowers.Bank.Transaction do
  @moduledoc """
  A payment out of the shop's account, as the bank booked it. The sync keeps
  each one it reads, so Jennie can see which have no receipt in the Expenses
  log.

  A payment has its receipt once a paid expense carries its bank id: the sync
  settled the expense with it, linked a card payment's receipt to it by amount
  and date, or Jennie linked it by hand. One that never has a receipt, such as a
  tax payment or a transfer to her own account, she dismisses.
  """

  use Ash.Resource,
    domain: Edenflowers.Bank,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  require Ash.Query

  alias Edenflowers.Events

  attributes do
    uuid_primary_key :id

    attribute :bank_id, :string do
      description "The bank's id for the payment, which an expense it pays keeps as its bank_transaction_id."
      allow_nil? false
    end

    attribute :booked_on, :date, allow_nil?: false

    attribute :amount, :decimal do
      description "What left the account, as a positive amount in `currency`."
      allow_nil? false
      constraints scale: 2
    end

    attribute :currency, :string do
      description "Lower case ISO code, as the bank sent it."
      allow_nil? false
    end

    attribute :counterparty, :string, description: "Who was paid, if the bank says."
    attribute :message, :string, description: "The payment's message, if any."
    attribute :reference_number, :string, description: "The reference the payment quoted, as the bank sent it."

    attribute :dismissed_at, :utc_datetime do
      description "When Jennie said this payment needs no receipt. Nil while it may need one."
    end

    timestamps()
  end

  relationships do
    has_one :expense, Edenflowers.Expenses.Expense do
      description "The expense that keeps this payment's bank id."
      source_attribute :bank_id
      destination_attribute :bank_transaction_id
    end
  end

  identities do
    identity :unique_bank_id, [:bank_id]
  end

  actions do
    defaults [:read]

    create :record do
      description "Keeps a booked payment out of the account. Reading it again changes nothing Jennie did to it."
      upsert? true
      upsert_identity :unique_bank_id
      upsert_fields [:counterparty, :message]
      accept [:bank_id, :booked_on, :amount, :currency, :counterparty, :message, :reference_number]
    end

    read :awaiting_receipt do
      description "Payments not dismissed and not yet paying an expense, oldest first: the ones linking tries."
      filter expr(is_nil(dismissed_at) and not exists(expense, paid))
      prepare build(sort: [booked_on: :asc])
    end

    read :missing_receipt do
      description "Payments Jennie should find a receipt for: not dismissed, paying no expense, and booked over " <>
                    "three days ago or in a month that has ended. So a card receipt has three days to arrive, and on the " <>
                    "1st the whole previous month is checked for the accountant's report. Newest first."

      filter expr(is_nil(dismissed_at) and not exists(expense, paid))

      prepare fn query, _context ->
        today = Edenflowers.ShopTime.today()
        cutoff = Enum.max([Date.add(today, -3), Date.beginning_of_month(today)], Date)
        Ash.Query.filter(query, booked_on < ^cutoff)
      end

      prepare build(sort: [booked_on: :desc])
    end

    read :dismissed do
      description "Payments Jennie said need no receipt, newest first."
      filter expr(not is_nil(dismissed_at))
      prepare build(sort: [booked_on: :desc])
    end

    update :dismiss do
      description "Jennie says this payment needs no receipt."
      accept []
      change set_attribute(:dismissed_at, &DateTime.utc_now/0)
    end

    update :restore do
      description "Undoes dismiss: the payment may need a receipt after all."
      accept []
      change set_attribute(:dismissed_at, nil)
    end

    action :link_receipts do
      description "Links each payment awaiting a receipt to the paid expense of its amount and currency paid " <>
                    "within a week of the booking, such as a card payment's receipt. Leaves the expense's paid " <>
                    "date alone and skips a pair Jennie unlinked."

      run Edenflowers.Bank.Actions.LinkReceipts
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if action_type(:read)
      authorize_if action([:record, :link_receipts])
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy always() do
      forbid_if always()
    end
  end

  # The Expenses page and the Overview list the payments missing a receipt.
  pub_sub do
    module EdenflowersWeb.Endpoint

    publish_all :create, Events.admin_bank()
    publish_all :update, Events.admin_bank()
  end

  postgres do
    table "bank_transactions"
    repo Edenflowers.Repo
    migration_types amount: :decimal
  end
end
