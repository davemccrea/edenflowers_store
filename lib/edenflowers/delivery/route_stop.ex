defmodule Edenflowers.Delivery.RouteStop do
  use Ash.Resource,
    domain: Edenflowers.Delivery,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias Edenflowers.Delivery.RouteStop.Changes

  postgres do
    table "route_stops"
    repo Edenflowers.Repo

    references do
      reference :route, on_delete: :delete
    end
  end

  code_interface do
    define :list_for_date, action: :for_date, args: [:date]
    define :record_delivered, action: :record_delivered
    define :record_failed, action: :record_failed
  end

  @doc "Order ids already on a published route for the given day — the eligibility exclusion set."
  def published_order_ids(date) do
    date
    |> list_for_date!(query: [select: [:order_id]], authorize?: false)
    |> Enum.map(& &1.order_id)
  end

  actions do
    defaults [:read]

    # A stop snapshots the order's delivery details at publish; only the order's
    # cancellation/refund status is read live later. Leg metrics come from the optimizer's
    # accepted draft. Status starts pending and is overwritten when the driver records an outcome.
    create :create do
      primary? true

      accept [
        :sequence,
        :order_id,
        :order_reference,
        :recipient_name,
        :recipient_phone,
        :delivery_address,
        :delivery_instructions,
        :card_message,
        :products,
        :position,
        :leg_distance_m,
        :leg_duration_s
      ]
    end

    read :for_date do
      argument :date, :date, allow_nil?: false
      filter expr(route.date == ^arg(:date))
    end

    # The driver records exactly one current outcome per stop; recording again overwrites it
    # (no kept history). "Other" demands a note; otherwise the note is optional. A delivered
    # outcome also marks the order fulfilled via the order's existing bypass.
    update :record_delivered do
      accept [:delivery_method, :outcome_note]
      require_atomic? false

      validate present(:delivery_method)

      validate present(:outcome_note),
        where: [attribute_equals(:delivery_method, :other)],
        message: "is required when the method is Other"

      change set_attribute(:status, :delivered)
      change set_attribute(:failure_reason, nil)
      change set_attribute(:outcome_recorded_at, &DateTime.utc_now/0)
      change Changes.MarkOrderFulfilled
    end

    update :record_failed do
      accept [:failure_reason, :outcome_note]
      require_atomic? false

      validate present(:failure_reason)

      validate present(:outcome_note),
        where: [attribute_equals(:failure_reason, :other)],
        message: "is required when the reason is Other"

      change set_attribute(:status, :failed)
      change set_attribute(:delivery_method, nil)
      change set_attribute(:outcome_recorded_at, &DateTime.utc_now/0)
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy always() do
      forbid_if always()
    end
  end

  pub_sub do
    module EdenflowersWeb.Endpoint
    prefix "route_stop"

    # Per-route topic so the florist's monitor (slice 8) subscribes to one route at a time.
    publish :record_delivered, ["outcome", :route_id]
    publish :record_failed, ["outcome", :route_id]
  end

  preparations do
    prepare build(sort: [sequence: :asc])
  end

  attributes do
    uuid_primary_key :id

    attribute :sequence, :integer, allow_nil?: false

    attribute :status, :atom do
      allow_nil? false
      default :pending
      constraints one_of: [:pending, :delivered, :failed, :skipped]
    end

    # The single current outcome. Exactly one of delivery_method / failure_reason is set, matching
    # status; recording again overwrites both. The note is required only when "other" is chosen.
    attribute :delivery_method, :atom do
      constraints one_of: [:handed_to_recipient, :left_in_safe_place, :other]
    end

    attribute :failure_reason, :atom do
      constraints one_of: [:recipient_unavailable, :could_not_access, :could_not_find, :refused, :other]
    end

    attribute :outcome_note, :string
    attribute :outcome_recorded_at, :utc_datetime

    attribute :order_reference, :string, allow_nil?: false
    attribute :recipient_name, :string
    attribute :recipient_phone, :string
    attribute :delivery_address, :string
    attribute :delivery_instructions, :string
    attribute :card_message, :string

    # Snapshotted product lines as `%{"name" => ..., "quantity" => ...}` maps; prices are
    # deliberately excluded — the driver never sees them.
    attribute :products, {:array, :map}, allow_nil?: false, default: []

    # HERE "lat,lng" snapshotted from the order, for the driver page's directions link.
    attribute :position, :string

    attribute :leg_distance_m, :integer, allow_nil?: false
    attribute :leg_duration_s, :integer, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :route, Edenflowers.Delivery.Route, allow_nil?: false
    belongs_to :order, Edenflowers.Store.Order, allow_nil?: false
  end
end
