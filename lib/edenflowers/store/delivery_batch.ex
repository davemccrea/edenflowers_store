defmodule Edenflowers.Store.DeliveryBatch do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "delivery_batches"
    repo Edenflowers.Repo
  end

  code_interface do
    define :get_by_id, action: :by_id, args: [:id]
    define :list_for_date, action: :for_date, args: [:delivery_date]
  end

  actions do
    defaults [:read, create: [:delivery_date, :published_by_user_id, :published_at]]

    read :by_id do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
    end

    read :for_date do
      argument :delivery_date, :date, allow_nil?: false
      filter expr(delivery_date == ^arg(:delivery_date))
      prepare build(sort: [published_at: :asc])
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

    attribute :delivery_date, :date, allow_nil?: false
    attribute :published_at, :utc_datetime, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :published_by, Edenflowers.Accounts.User do
      source_attribute :published_by_user_id
      allow_nil? false
    end

    has_many :trips, Edenflowers.Store.DeliveryTrip, destination_attribute: :batch_id
  end
end
