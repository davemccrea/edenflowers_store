defmodule Edenflowers.Orders.Subscription do
  @moduledoc """
  A customer's standing request for a florist's-choice bouquet every few
  weeks. Not an order: it creates ordinary orders, its Occurrences, from the
  delivery details of the first one. See ADR 0003.
  """
  use Ash.Resource,
    domain: Edenflowers.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine, AshOban, AshPaperTrail.Resource]

  @intervals [1, 2, 4]

  # Notice Jennie gets to buy the flowers before an Occurrence is delivered.
  @lead_days 3

  # A customer's changes close a day before the occurrence job charges the card.
  @cutoff_days @lead_days + 1

  def intervals, do: @intervals

  @doc """
  The day a closed subscription opens to changes again: the occurrence job
  creates the next Occurrence then and moves on to the following date.
  """
  def changes_reopen_on(%{next_fulfillment_date: date}), do: charged_on(date)

  @doc "The day the occurrence job charges the card for a delivery on `date`."
  def charged_on(date), do: Date.add(date, -@lead_days)

  @doc "Whether a customer can still change an occurrence scheduled for `date`."
  def changes_open_for?(date) do
    Date.after?(date, Date.add(Edenflowers.Expressions.HelsinkiToday.today(), @cutoff_days))
  end

  @doc "The next delivery date a paused subscription would get if it resumed today."
  def resume_date(%{next_fulfillment_date: date, interval_weeks: weeks}) do
    Edenflowers.Orders.Changes.StepToScheduledDate.scheduled_date(date, weeks, @cutoff_days)
  end

  def lead_days, do: @lead_days

  def cutoff_days, do: @cutoff_days

  @doc "The subscription's Occurrence still waiting on its payment link, among `orders`."
  def unpaid_occurrence(orders, %{id: id}) do
    Enum.find(orders, &(&1.subscription_id == id and &1.payment_link_open?))
  end

  @doc "Starts a subscription held at `:payment_failed` making Occurrences again."
  def reactivate_if_held(%{state: :payment_failed} = subscription) do
    Edenflowers.Orders.reactivate_subscription(subscription, actor: Edenflowers.Actors.system_actor())
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
        default_actor Edenflowers.Actors.system_actor()
        where expr(state == :active and next_fulfillment_date <= date_add(helsinki_today(), ^@lead_days, :day))
      end

      # Queued only by :activate, so subscriptions started before this email
      # existed are never sent one.
      trigger :send_setup_email do
        action :send_setup_email
        queue :default
        max_attempts 20
        lock_for_update? false
        scheduler_cron false
        worker_module_name Edenflowers.Orders.Workers.SendSubscriptionSetupEmail
        scheduler_module_name Edenflowers.Orders.Schedulers.SendSubscriptionSetupEmail
        default_actor Edenflowers.Actors.system_actor()
        where expr(is_nil(setup_emailed_at))
      end
    end
  end

  paper_trail do
    change_tracking_mode :changes_only
    store_action_name? true
    ignore_attributes [:inserted_at, :updated_at]
  end

  actions do
    defaults [:read]

    read :admin_list do
      pagination offset?: true, keyset?: true, countable: true, required?: false
      prepare build(sort: [next_fulfillment_date: :asc], load: [:user, :product_variant])
    end

    # A cancelled subscription drops off the account page a month after.
    read :mine do
      filter expr(user_id == ^actor(:id) and (state != :cancelled or updated_at > ago(30, :day)))

      prepare build(
                sort: [inserted_at: :asc],
                load: [
                  :changes_closed?,
                  :fulfillment_option,
                  product_variant: [product: :product_variants]
                ]
              )
    end

    create :activate do
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
      change Edenflowers.Orders.Changes.SnapshotCard
      change run_oban_trigger(:send_setup_email)
    end

    update :send_setup_email do
      accept []
      transaction? false
      require_atomic? false
      change Edenflowers.Orders.Changes.SendSubscriptionSetupEmail
    end

    update :create_occurrence do
      accept []
      transaction? false
      require_atomic? false
      change Edenflowers.Orders.Changes.CreateOccurrence
    end

    # Dates that passed while it was held are not owed, so it picks up at the
    # first one not yet past.
    update :reactivate do
      change transition_state(:active)
      change {Edenflowers.Orders.Changes.StepToScheduledDate, days_from_today: 0}
      require_atomic? false
    end

    update :pause do
      validate Edenflowers.Orders.Validations.SubscriptionChangesOpen
      change transition_state(:paused)
    end

    # Picks up at the first date on the schedule the occurrence job hasn't
    # already passed, so resuming never creates an Occurrence at short notice.
    update :resume do
      change transition_state(:active)
      change {Edenflowers.Orders.Changes.StepToScheduledDate, days_from_today: @cutoff_days}
      require_atomic? false
    end

    # The occurrence job reads the subscription when it creates each
    # Occurrence, so a change applies from the next one. A new interval or
    # delivery day also moves that next date; see Reschedule.
    update :change do
      accept [:product_variant_id, :interval_weeks]
      argument :delivery_day, Edenflowers.Fulfillment.Weekday
      validate attribute_does_not_equal(:state, :cancelled)
      validate attribute_in(:interval_weeks, @intervals)
      validate Edenflowers.Orders.Validations.SubscriptionVariant
      validate Edenflowers.Orders.Validations.SubscriptionDeliveryDay
      validate Edenflowers.Orders.Validations.SubscriptionChangesOpen
      change Edenflowers.Orders.Changes.Reschedule
      require_atomic? false
    end

    # The new card settles nothing already owed: an unpaid Occurrence keeps its
    # payment link. A held subscription goes back to charging the new card.
    update :replace_card do
      argument :stripe_payment_method_id, :string, allow_nil?: false
      validate attribute_does_not_equal(:state, :cancelled)
      change set_attribute(:stripe_payment_method_id, arg(:stripe_payment_method_id))
      change Edenflowers.Orders.Changes.SnapshotCard

      change after_action(fn _changeset, subscription, _context -> reactivate_if_held(subscription) end)

      require_atomic? false
    end

    update :cancel do
      change transition_state(:cancelled)
      change Edenflowers.Orders.Changes.CancelOpenOccurrences
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

    timestamps()
  end

  relationships do
    belongs_to :user, Edenflowers.Accounts.User, allow_nil?: false
    belongs_to :product_variant, Edenflowers.Catalog.ProductVariant, allow_nil?: false
    belongs_to :fulfillment_option, Edenflowers.Fulfillment.FulfillmentOption, allow_nil?: false
    has_many :orders, Edenflowers.Orders.Order
  end

  calculations do
    # True from 24 hours before the occurrence job would create and charge the
    # next Occurrence (`@lead_days` before delivery), counted in Helsinki days.
    # Only an active subscription has an Occurrence coming.
    calculate :changes_closed?,
              :boolean,
              expr(state == :active and next_fulfillment_date <= date_add(helsinki_today(), ^@cutoff_days, :day))

    # Occurrences carry no promotion, so only the order that started the
    # subscription can have been discounted.
    calculate :first_order_discounted?, :boolean, expr(exists(orders, origin == :online and promotion_applied?))
  end

  aggregates do
    # The schedule runs on from the latest delivery, booked or done.
    max :last_delivery_date, :orders, :fulfillment_date do
      filter expr(state == :placed and fulfillment_status != :cancelled)
    end

    min :first_delivery_date, :orders, :fulfillment_date do
      filter expr(origin == :online)
    end
  end
end
