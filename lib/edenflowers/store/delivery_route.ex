defmodule Edenflowers.Store.DeliveryRoute do
  @moduledoc """
  One record per driver per delivery date.

  A daily route holds the immutable trips published throughout the day. Drivers
  reach their route through a high-entropy secret link; only the SHA-256
  `token_hash` is persisted, never the raw token. Admins monitor and record
  outcomes on a driver's behalf, but are never themselves a route assignee.
  """
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "delivery_routes"
    repo Edenflowers.Repo
  end

  code_interface do
    define :get_by_id, action: :by_id, args: [:id]
    define :for_date, action: :for_date, args: [:delivery_date]
    define :by_token_hash, action: :by_token_hash, args: [:token_hash]
    define :mark_first_published, action: :mark_first_published
    define :mark_email_queued, action: :mark_email_queued
  end

  actions do
    defaults [
      :read,
      create: [:delivery_date, :driver_id, :token_hash, :first_published_at]
    ]

    read :by_id do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
    end

    read :for_date do
      argument :delivery_date, :date, allow_nil?: false
      filter expr(delivery_date == ^arg(:delivery_date))
      prepare build(sort: [inserted_at: :asc])
    end

    # Secret-link lookup. The caller hashes the presented raw token and matches
    # the stored hash; the route page then authorizes by token rather than user.
    read :by_token_hash do
      argument :token_hash, :string, allow_nil?: false, sensitive?: true
      filter expr(token_hash == ^arg(:token_hash))
      get? true
    end

    update :mark_first_published do
      change set_attribute(:first_published_at, &DateTime.utc_now/0)
    end

    update :mark_email_queued do
      change set_attribute(:first_email_queued_at, &DateTime.utc_now/0)
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

    # Stored only so the secret link can be matched; never returned through
    # normal reads.
    attribute :token_hash, :string, sensitive?: true

    attribute :first_published_at, :utc_datetime
    attribute :first_email_queued_at, :utc_datetime

    timestamps()
  end

  relationships do
    belongs_to :driver, Edenflowers.Store.Driver, allow_nil?: false

    has_many :trips, Edenflowers.Store.DeliveryTrip do
      sort sequence: :asc
    end
  end

  identities do
    identity :unique_driver_date, [:driver_id, :delivery_date]
    identity :unique_token_hash, [:token_hash]
  end
end
