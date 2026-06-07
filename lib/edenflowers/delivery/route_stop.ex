defmodule Edenflowers.Delivery.RouteStop do
  use Ash.Resource,
    domain: Edenflowers.Delivery,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "route_stops"
    repo Edenflowers.Repo

    references do
      reference :route, on_delete: :delete
    end
  end

  code_interface do
    define :list_for_date, action: :for_date, args: [:date]
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
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy always() do
      forbid_if always()
    end
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
