defmodule Edenflowers.Orders.OrderRepeat do
  @moduledoc """
  The schedule of a Repeating order: how many weeks apart, and the next date
  to place. Its job copies the latest order of the series to that date 14
  days ahead, so the schedule, not the orders' own dates, decides when the
  next one is: moving one delivery leaves the rest where they were.
  """
  use Ash.Resource,
    domain: Edenflowers.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  import Edenflowers.Actors

  alias Edenflowers.Orders.Changes.NotifyShop
  alias Edenflowers.Orders.Validations.Holds

  # Far enough ahead that the next order shows on the Overview and can be invoiced.
  @days_ahead 14

  attributes do
    uuid_primary_key :id

    attribute :every_weeks, :integer do
      allow_nil? false
      description "How many weeks apart the orders are: 1, 2 or 4."
    end

    attribute :next_on, :date do
      description "The date the next order is placed for. Nil once Jennie stops repeating."
    end

    timestamps()
  end

  relationships do
    has_many :orders, Edenflowers.Orders.Order

    has_one :latest_order, Edenflowers.Orders.Order do
      description "The order placed last, which the next one copies, cancelled or not."
      from_many? true
      sort inserted_at: :desc
    end
  end

  calculations do
    calculate :active?, :boolean, expr(not is_nil(next_on)) do
      description "Whether more orders will be placed."
    end
  end

  actions do
    defaults [:read]

    create :start do
      description "Starts the schedule when Jennie places a Custom Order that repeats."
      accept [:every_weeks, :next_on]
      validate attribute_in(:every_weeks, [1, 2, 4])
    end

    update :place_next do
      description "Run by its job #{@days_ahead} days before `next_on`: places a copy of the latest order for " <>
                    "that date and moves `next_on` on. A cancelled latest order is copied all the same."

      accept []
      validate {Holds, calculation: :active?, message: "has stopped"}
      change Edenflowers.Orders.OrderRepeat.Changes.PlaceNext
      require_atomic? false
    end

    update :stop do
      description "Ends the repeat: no order is placed after the ones already placed."
      accept []
      change set_attribute(:next_on, nil)
    end

    update :report_failure do
      description "The job ran out of attempts to place the next order. Tells Jennie; tomorrow's run tries again."
      accept []
      change {NotifyShop, notice: :repeat_failed}
      require_atomic? false
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if action([:place_next, :report_failure])
      authorize_if action_type(:read)
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if action([:start, :stop])
      authorize_if action_type(:read)
    end
  end

  oban do
    triggers do
      trigger :place_next do
        action :place_next
        queue :default
        max_attempts 3
        scheduler_cron "0 6 * * *"
        on_error :report_failure
        worker_module_name Edenflowers.Orders.Workers.PlaceNextRepeat
        scheduler_module_name Edenflowers.Orders.Schedulers.PlaceNextRepeat
        default_actor system_actor()
        where expr(active? and next_on <= date_add(helsinki_today(), ^@days_ahead, :day))
      end
    end
  end

  postgres do
    repo Edenflowers.Repo
    table "order_repeats"
  end
end
