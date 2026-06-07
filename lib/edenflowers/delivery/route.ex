defmodule Edenflowers.Delivery.Route do
  use Ash.Resource,
    domain: Edenflowers.Delivery,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "routes"
    repo Edenflowers.Repo
  end

  code_interface do
    define :publish, action: :publish
    define :list_published_for_date, action: :published_for_date, args: [:date]
    define :list_for_driver, action: :for_driver, args: [:driver_id, :date]
  end

  actions do
    defaults [:read]

    # One published route for one driver: the day-scoped header plus its ordered, snapshotted
    # stops. The whole run is published inside a transaction (see DeliveriesLive), so a failure
    # on any route persists nothing.
    create :publish do
      accept [:date, :driver_id]

      argument :stops, {:array, :map}, allow_nil?: false

      change set_attribute(:published_at, &DateTime.utc_now/0)
      change manage_relationship(:stops, :route_stops, type: :create)
    end

    read :published_for_date do
      description "Today's published routes, for the planning page's monitoring view."
      argument :date, :date, allow_nil?: false
      filter expr(date == ^arg(:date))

      prepare build(sort: [published_at: :asc], load: [:driver, :route_stops])
    end

    read :for_driver do
      description "One driver's published routes for a day — the public /d/:token page (read with the token as the gate)."
      argument :driver_id, :uuid, allow_nil?: false
      argument :date, :date, allow_nil?: false
      filter expr(driver_id == ^arg(:driver_id) and date == ^arg(:date))

      prepare build(sort: [published_at: :asc], load: [:route_stops])
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

  attributes do
    uuid_primary_key :id

    attribute :date, :date, allow_nil?: false
    attribute :published_at, :utc_datetime, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :driver, Edenflowers.Delivery.Driver, allow_nil?: false
    has_many :route_stops, Edenflowers.Delivery.RouteStop
  end
end
