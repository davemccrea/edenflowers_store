defmodule Edenflowers.Orders.Subscription do
  @moduledoc """
  A customer's standing request for a subscribable product every few
  weeks. Not an order: it creates ordinary orders, its Occurrences, from the
  delivery details of the first one. See ADR 0003.
  """
  use Ash.Resource,
    domain: Edenflowers.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshStateMachine, AshOban, AshPaperTrail.Resource]

  import Edenflowers.Actors

  alias Edenflowers.Orders.Changes.NotifyShop
  alias Edenflowers.Orders.Subscription.Changes
  alias Edenflowers.Orders.Subscription.Validations
  alias Edenflowers.Orders.Validations.Holds

  @intervals [1, 2, 4]

  # Notice Jennie gets to buy the flowers before an Occurrence is delivered.
  @lead_days 2

  # The last day a customer can change or cancel is this many days before a
  # delivery. Changes close the day after, which must be no later than the
  # day the occurrence job charges the card.
  @change_deadline_days 3

  @cutoff_days @change_deadline_days - 1

  # The day before the change deadline, so the customer has two days to act.
  @heads_up_days @cutoff_days + 2

  def intervals, do: @intervals

  @doc """
  The day the occurrence job charges the card for a delivery on `date`. Checkout
  quotes it before the subscription exists; a subscription has `charged_on`.
  """
  def charged_on(date), do: Date.add(date, -@lead_days)

  def lead_days, do: @lead_days

  def cutoff_days, do: @cutoff_days

  def change_deadline_days, do: @change_deadline_days

  @doc "Starts a subscription held at `:payment_failed` making Occurrences again."
  def reactivate_if_held(%{state: :payment_failed} = subscription) do
    Edenflowers.Orders.reactivate_subscription(subscription, actor: system_actor())
  end

  def reactivate_if_held(subscription), do: {:ok, subscription}

  postgres do
    repo Edenflowers.Repo
    table "subscriptions"
  end

  # Created only once the first order is paid, so it starts active.
  state_machine do
    initial_states([:active])
    default_initial_state(:active)

    # A refused card holds the subscription until its Occurrence is paid
    # through the payment link.
    transitions do
      transition(:create_occurrence, from: :active, to: :payment_failed)
      transition(:reactivate, from: :payment_failed, to: :active)
      transition(:pause, from: :active, to: :paused)
      transition(:resume, from: :paused, to: :active)
      transition(:cancel, from: [:active, :paused, :payment_failed], to: :cancelled)
    end
  end

  oban do
    triggers do
      trigger :create_occurrence do
        action :create_occurrence
        queue :default
        max_attempts 20
        lock_for_update? false
        scheduler_cron "0 * * * *"
        worker_module_name Edenflowers.Orders.Workers.CreateOccurrence
        scheduler_module_name Edenflowers.Orders.Schedulers.CreateOccurrence
        default_actor system_actor()
        where expr(state == :active and next_fulfillment_date <= date_add(helsinki_today(), ^@lead_days, :day))
      end

      # Weekly subscribers get flowers too often to need telling. Daily, from
      # `@heads_up_days` before a delivery until its changes close, once per delivery.
      trigger :send_heads_up_email do
        action :send_heads_up_email
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron "0 7 * * *"
        worker_module_name Edenflowers.Orders.Workers.SendSubscriptionHeadsUpEmail
        scheduler_module_name Edenflowers.Orders.Schedulers.SendSubscriptionHeadsUpEmail
        default_actor system_actor()

        where expr(
                state == :active and interval_weeks in [2, 4] and
                  next_fulfillment_date > date_add(helsinki_today(), ^@cutoff_days, :day) and
                  next_fulfillment_date <= date_add(helsinki_today(), ^@heads_up_days, :day) and
                  (is_nil(heads_up_emailed_for) or heads_up_emailed_for != next_fulfillment_date)
              )
      end

      # Queued only by :activate, so subscriptions started before this email
      # existed are never sent one.
      trigger :send_setup_email do
        action :send_setup_email
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron false
        worker_module_name Edenflowers.Orders.Workers.SendSubscriptionSetupEmail
        scheduler_module_name Edenflowers.Orders.Schedulers.SendSubscriptionSetupEmail
        default_actor system_actor()
        where expr(is_nil(setup_emailed_at))
      end

      # Queued by :cancel when the customer cancels in their account.
      trigger :send_cancellation_confirmed_email do
        action :send_cancellation_confirmed_email
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron false
        worker_module_name Edenflowers.Orders.Workers.SendSubscriptionCancellationConfirmedEmail
        scheduler_module_name Edenflowers.Orders.Schedulers.SendSubscriptionCancellationConfirmedEmail
        default_actor system_actor()
      end

      # Queued by :cancel when Jennie cancels and ticks "email the customer".
      trigger :send_cancelled_email do
        action :send_cancelled_email
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron false
        worker_module_name Edenflowers.Orders.Workers.SendSubscriptionCancelledEmail
        scheduler_module_name Edenflowers.Orders.Schedulers.SendSubscriptionCancelledEmail
        default_actor system_actor()
      end
    end
  end

  paper_trail do
    change_tracking_mode :changes_only
    store_action_name? true
    ignore_attributes [:inserted_at, :updated_at]

    # Customers change their own subscriptions, so the log says whose change it
    # was. The system actor isn't a user, so automatic changes are left unnamed.
    belongs_to_actor :user, Edenflowers.Accounts.User, domain: Edenflowers.Accounts
  end

  actions do
    defaults [:read]

    read :admin_list do
      description "Every subscription for the admin list, paginated, soonest next delivery first."
      pagination offset?: true, keyset?: true, countable: true, required?: false
      prepare build(sort: [next_fulfillment_date: :asc], load: [:next_delivery_date, :user, :product_variant])
    end

    # Held until Jennie sorts out the card: no Occurrence is made meanwhile.
    read :payment_failed do
      description "Subscriptions held after a refused card, soonest next delivery first, for Jennie to follow up."
      filter expr(state == :payment_failed)
      prepare build(sort: [next_fulfillment_date: :asc], load: [:user, product_variant: :product])
    end

    read :mine do
      description "The actor's own subscriptions for their account page, leaving out cancelled ones " <>
                    "unless their final delivery is still on its way."

      # A cancelled one stays only while its final delivery is still on its way.
      filter expr(user_id == ^actor(:id) and (state != :cancelled or exists(booked_occurrence, true)))

      prepare build(
                sort: [inserted_at: :asc],
                load: [
                  :changes_closed?,
                  :changeable?,
                  :charged_on,
                  :changes_reopen_on,
                  :resume_date,
                  :next_delivery_date,
                  booked_occurrence: [:changes_open?],
                  unpaid_occurrence: [:grand_total],
                  product_variant: :product
                ]
              )
    end

    create :activate do
      description "Starts an active subscription from its first order once that is paid, snapshotting the card, " <>
                    "and queues the set-up email and a shop notice. System only."

      accept [
        :user_id,
        :product_variant_id,
        :interval_weeks,
        :next_fulfillment_date,
        :recipient_name,
        :recipient_phone_number,
        :delivery_address,
        :delivery_instructions,
        :fulfillment_option_id,
        :card_message,
        :locale,
        :stripe_customer_id,
        :stripe_payment_method_id
      ]

      validate attribute_in(:interval_weeks, @intervals)
      change Changes.SnapshotCard
      change run_oban_trigger(:send_setup_email)
      change NotifyShop
    end

    update :send_cancelled_email do
      description "Emails the customer Subscription cancelled with Jennie's message, naming an already-charged " <>
                    "delivery that still comes. Queued by :cancel when Jennie ticks to email the customer."

      accept []
      argument :message, :string
      transaction? false
      require_atomic? false
      change {Changes.SendSubscriptionCancelledEmail, email: :cancelled}
    end

    update :send_cancellation_confirmed_email do
      description "Confirms to the customer by email that they cancelled their subscription in their account, " <>
                    "naming an already-charged delivery that still comes. Queued by :cancel."

      accept []
      transaction? false
      require_atomic? false
      change {Changes.SendSubscriptionCancelledEmail, email: :cancellation_confirmed}
    end

    update :send_setup_email do
      description "Emails the customer that their subscription is set up and stamps setup_emailed_at. " <>
                    "Queued only by :activate."

      accept []
      transaction? false
      require_atomic? false
      change Changes.SendSubscriptionSetupEmail
    end

    update :send_heads_up_email do
      description "Tells a two- or four-weekly subscriber their next delivery is coming while they can still " <>
                    "change it, and stamps heads_up_emailed_for so each delivery gets one. Run daily by Oban."

      accept []
      transaction? false
      require_atomic? false
      change Changes.SendSubscriptionHeadsUpEmail
    end

    update :create_occurrence do
      description "On the Charge day, creates the next Occurrence, charges the saved card and moves the next date " <>
                    "on one interval. A refused card leaves the order unpaid with a Payment Link and holds the " <>
                    "subscription at payment_failed. Run hourly by Oban; safe to retry."

      accept []
      transaction? false
      require_atomic? false
      change Changes.CreateOccurrence
    end

    # Dates that passed while it was held are not owed, so it picks up at the
    # first one not yet past.
    update :reactivate do
      description "Returns a subscription held at payment_failed to active once its unpaid Occurrence is paid " <>
                    "or its card replaced. System only."

      change transition_state(:active)
      change {Changes.StepToScheduledDate, days_from_today: 0}
      require_atomic? false
    end

    update :pause do
      description "Stops an active subscription creating Occurrences until it is resumed. A customer can only " <>
                    "before the Change deadline; Jennie can anytime."

      validate {Holds, calculation: :pausable?, message: "can't be paused"}
      validate Validations.SubscriptionChangesOpen
      change transition_state(:paused)
    end

    # Picks up at the first date on the schedule still open to changes, so
    # resuming never creates an Occurrence at short notice.
    update :resume do
      description "Makes a paused subscription active again from the first scheduled date still open to changes."
      validate {Holds, calculation: :resumable?, message: "can't be resumed"}
      change transition_state(:active)
      change {Changes.StepToScheduledDate, days_from_today: @change_deadline_days}

      # The customer has just chosen it, so a delivery already due its
      # heads-up goes without.
      change fn changeset, _context ->
        date = Ash.Changeset.get_attribute(changeset, :next_fulfillment_date)

        if Date.diff(date, Edenflowers.ShopTime.today()) <= @heads_up_days,
          do: Ash.Changeset.force_change_attribute(changeset, :heads_up_emailed_for, date),
          else: changeset
      end

      require_atomic? false
    end

    # The occurrence job reads the subscription when it creates each
    # Occurrence, so a change applies from the next one. A new interval or
    # delivery day also moves that next date; see Reschedule.
    update :change do
      description "Changes the size, interval or delivery day from the next Occurrence on, moving the next date " <>
                    "to fit. A customer can only before the Change deadline; Jennie can anytime."

      accept [:product_variant_id, :interval_weeks]
      argument :delivery_day, Edenflowers.Fulfillment.Weekday
      validate attribute_does_not_equal(:state, :cancelled)
      validate attribute_in(:interval_weeks, @intervals)
      validate Validations.SubscriptionVariant
      validate Validations.SubscriptionDeliveryDay
      validate Validations.SubscriptionChangesOpen
      change Changes.Reschedule
      require_atomic? false
    end

    # The new card settles nothing already owed: an unpaid Occurrence keeps its
    # payment link. A held subscription goes back to charging the new card.
    update :replace_card do
      description "Saves a new card for future charges from a succeeded SetupIntent, and reactivates a subscription " <>
                    "held at payment_failed. An unpaid Occurrence keeps its Payment Link."

      argument :stripe_payment_method_id, :string, allow_nil?: false
      validate attribute_does_not_equal(:state, :cancelled)
      change set_attribute(:stripe_payment_method_id, arg(:stripe_payment_method_id))
      change Changes.SnapshotCard

      change after_action(fn _changeset, subscription, _context -> reactivate_if_held(subscription) end)

      require_atomic? false
    end

    update :cancel do
      description "Ends the subscription for good, also cancelling and refunding Occurrences still open to changes. " <>
                    "A customer's cancel emails them a confirmation and notifies the shop."

      validate {Holds, calculation: :cancellable?, message: "can't be cancelled"}

      argument :email_customer?, :boolean,
        default: true,
        description: "Whether Jennie's cancel emails the customer. A customer's own cancel always confirms by email."

      argument :message, :string, description: "Jennie's note in the cancelled email."
      change transition_state(:cancelled)
      change Changes.CancelOpenOccurrences
      change Changes.QueueSubscriptionCancelledEmail
      require_atomic? false
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if action([
                     :activate,
                     :create_occurrence,
                     :reactivate,
                     :send_setup_email,
                     :send_heads_up_email,
                     :send_cancelled_email,
                     :send_cancellation_confirmed_email,
                     :replace_card
                   ])

      authorize_if action_type(:read)
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if action_type(:read)
      authorize_if action([:pause, :resume, :cancel, :change])
    end

    policy action([:read, :mine, :pause, :resume, :cancel, :change, :replace_card]) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  # Refreshes the admin's subscription pages, which have no pull to refresh.
  pub_sub do
    module EdenflowersWeb.Endpoint

    publish_all :create, ["admin", "subscriptions"]
    publish_all :update, ["admin", "subscriptions"]
  end

  attributes do
    uuid_primary_key :id

    attribute :interval_weeks, :integer, allow_nil?: false
    attribute :next_fulfillment_date, :date, allow_nil?: false

    # Copied from the first order. Each occurrence prices its fee afresh from
    # the address, so no fee or geocode is kept here.
    attribute :recipient_name, :string
    attribute :recipient_phone_number, :string
    attribute :delivery_address, :string
    attribute :delivery_instructions, :string
    attribute :card_message, :string
    attribute :locale, :string, allow_nil?: false

    attribute :stripe_customer_id, :string, allow_nil?: false
    attribute :stripe_payment_method_id, :string, allow_nil?: false

    # Shown to the customer only; Stripe holds the card.
    attribute :card_brand, :string
    attribute :card_last4, :string
    attribute :card_exp_month, :integer
    attribute :card_exp_year, :integer

    attribute :setup_emailed_at, :utc_datetime
    # The delivery the last heads-up was about.
    attribute :heads_up_emailed_for, :date

    timestamps()
  end

  relationships do
    belongs_to :user, Edenflowers.Accounts.User do
      description "The customer who subscribed and manages it from their account."
      allow_nil? false
    end

    belongs_to :product_variant, Edenflowers.Catalog.ProductVariant do
      description "The size each Occurrence is made in; the customer can change it until the Change deadline."
      allow_nil? false
    end

    belongs_to :fulfillment_option, Edenflowers.Fulfillment.FulfillmentOption do
      description "Delivery or pickup for every Occurrence, copied from the first order."
      allow_nil? false
    end

    has_many :orders, Edenflowers.Orders.Order do
      description "The first order that started it (origin :online) and every Occurrence it has created."
    end

    has_one :unpaid_occurrence, Edenflowers.Orders.Order do
      description "The Occurrence whose card was refused, still waiting on its Payment Link, or nil."
      from_many? true
      filter expr(payment_link_open?)
      sort fulfillment_date: :asc
    end

    has_one :booked_occurrence, Edenflowers.Orders.Order do
      description "The next uncancelled order from today on (Helsinki time). The occurrence job books each " <>
                    "delivery ahead of its date, after which next_fulfillment_date has already moved on to the " <>
                    "one after."

      from_many? true
      filter expr(fulfillment_status != :cancelled and fulfillment_date >= helsinki_today())
      sort fulfillment_date: :asc
    end
  end

  calculations do
    calculate :next_delivery_date, :date, expr(if(state == :active, do: next_fulfillment_date, else: nil)) do
      description "The next Occurrence's delivery or pickup date, or nil unless active: only an active " <>
                    "subscription has an Occurrence coming."
    end

    calculate :charged_on, :date, expr(date_add(next_fulfillment_date, ^(-@lead_days), :day)) do
      description "The Charge day for the next delivery, 2 days before it: when the occurrence job creates its " <>
                    "order and charges the saved card."
    end

    calculate :change_deadline, :date, expr(date_add(next_fulfillment_date, ^(-@change_deadline_days), :day)) do
      description "The Change deadline for the next delivery, 3 days before it: the last day the customer can " <>
                    "pause, change or cancel it."
    end

    calculate :changes_reopen_on, :date, expr(charged_on) do
      description "When a subscription closed to changes opens again: the Charge day, when the occurrence job " <>
                    "creates the next Occurrence and moves on to the following date."
    end

    calculate :resume_date,
              :date,
              {Edenflowers.Orders.Subscription.Calculations.ScheduledDate, days_from_today: @change_deadline_days} do
      description "The next delivery date a paused subscription would get if it resumed today: the first " <>
                    "scheduled date still open to changes."
    end

    calculate :pausable?, :boolean, expr(state == :active) do
      description "Whether its state allows pausing. Ignores the Change deadline, so it also governs Jennie, " <>
                    "who may act inside it."
    end

    calculate :resumable?, :boolean, expr(state == :paused) do
      description "Whether its state allows resuming. Ignores the Change deadline, so it also governs Jennie, " <>
                    "who may act inside it."
    end

    calculate :cancellable?, :boolean, expr(state in [:active, :paused, :payment_failed]) do
      description "Whether it isn't cancelled yet. Ignores the Change deadline, so it also governs Jennie, " <>
                    "who may act inside it."
    end

    calculate :changeable?, :boolean, expr(state in [:active, :paused] and not changes_closed?) do
      description "Whether the customer can pause, resume or change it from their account now."
    end

    calculate :changes_closed?,
              :boolean,
              expr(state == :active and next_fulfillment_date <= date_add(helsinki_today(), ^@cutoff_days, :day)) do
      description "Whether the next delivery is past its Change deadline, from the day after it in Helsinki time. " <>
                    "Only an active subscription has an Occurrence coming, so otherwise false."
    end

    calculate :first_order_discounted?, :boolean, expr(exists(orders, origin == :online and promotion_applied?)) do
      description "Whether the order that started it had a promotion, for the set-up email. Occurrences carry " <>
                    "no promotion, so only that order can have been discounted."
    end
  end

  aggregates do
    max :last_delivery_date, :orders, :fulfillment_date do
      description "The latest delivery date of its placed, uncancelled orders, booked or done. The schedule " <>
                    "runs on from it when the interval or delivery day changes."

      filter expr(state == :placed and fulfillment_status != :cancelled)
    end

    min :first_delivery_date, :orders, :fulfillment_date do
      description "The delivery date of the order that started it, for the set-up email."
      filter expr(origin == :online)
    end

    first :first_order_fulfillment_fee, :orders, :fulfillment_fee do
      description "The first order's delivery fee in euros. Each Occurrence prices delivery afresh to the same " <>
                    "address, so it is what later ones cost too, for the set-up and heads-up emails."

      filter expr(origin == :online)
    end
  end
end
