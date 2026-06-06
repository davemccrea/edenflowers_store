defmodule Edenflowers.Store.DeliveryStop do
  @moduledoc """
  The persisted, published position of one order within a trip.

  An order has at most one delivery stop while its assignment is active; the
  eligibility read and publication transaction enforce that an order is not
  already assigned to an open route. Leg metrics are measured from the preceding
  stop (or the shop, for the first stop). Distances are in metres; durations are
  in seconds.
  """
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "delivery_stops"
    repo Edenflowers.Repo

    references do
      reference :order, index?: true
    end
  end

  code_interface do
    define :get_by_id, action: :by_id, args: [:id]
  end

  actions do
    defaults [
      :read,
      create: [:delivery_trip_id, :order_id, :sequence, :leg_distance, :leg_duration]
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
    attribute :leg_distance, :integer, allow_nil?: false
    attribute :leg_duration, :integer, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :delivery_trip, Edenflowers.Store.DeliveryTrip, allow_nil?: false
    belongs_to :order, Edenflowers.Store.Order, allow_nil?: false

    has_many :attempts, Edenflowers.Store.DeliveryAttempt do
      sort recorded_at: :asc
    end
  end

  identities do
    identity :unique_trip_sequence, [:delivery_trip_id, :sequence]
  end
end
