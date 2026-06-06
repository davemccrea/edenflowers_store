defmodule Edenflowers.Store.DeliveryTrip do
  @moduledoc """
  An immutable, published optimization result appended to a daily route.

  A daily route accumulates one trip per publication. Earlier trips and their
  stop order are never recalculated. A supplemental trip records the return leg
  back to the shop that precedes it, since return-to-shop is derived between
  consecutive trips rather than modeled as a stop.

  Distances are in metres; durations are in seconds.
  """
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "delivery_trips"
    repo Edenflowers.Repo
  end

  code_interface do
    define :get_by_id, action: :by_id, args: [:id]
  end

  actions do
    defaults [
      :read,
      create: [
        :delivery_route_id,
        :batch_id,
        :sequence,
        :distance,
        :driving_duration,
        :service_duration,
        :return_leg_distance,
        :return_leg_duration,
        :published_at
      ]
    ]

    read :by_id do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    bypass actor_attribute_equals(:system, true) do
      authorize_if always()
    end

    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :sequence, :integer, allow_nil?: false

    attribute :distance, :integer, allow_nil?: false
    attribute :driving_duration, :integer, allow_nil?: false
    attribute :service_duration, :integer, allow_nil?: false

    # Present only on supplemental trips: the leg from the driver's previous
    # final stop back to the shop, rendered as a return-to-shop row.
    attribute :return_leg_distance, :integer
    attribute :return_leg_duration, :integer

    attribute :published_at, :utc_datetime, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :delivery_route, Edenflowers.Store.DeliveryRoute, allow_nil?: false
    belongs_to :batch, Edenflowers.Store.DeliveryBatch, allow_nil?: false

    has_many :stops, Edenflowers.Store.DeliveryStop do
      sort sequence: :asc
    end
  end

  identities do
    identity :unique_route_sequence, [:delivery_route_id, :sequence]
  end
end
