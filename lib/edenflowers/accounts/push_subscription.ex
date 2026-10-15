defmodule Edenflowers.Accounts.PushSubscription do
  @moduledoc """
  One admin device's Web Push subscription, as the browser's `PushManager`
  hands it over. The setting is per device, so an admin has one per phone or
  browser that turned order notifications on.
  """
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "push_subscriptions"
    repo Edenflowers.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    # A device stops getting order notifications once its user is no longer an admin.
    read :admin_devices do
      filter expr(user.admin == true)
    end

    # A browser re-subscribing hands back the same endpoint, possibly with new
    # keys, so it replaces the row rather than adding one.
    create :subscribe do
      accept [:endpoint, :p256dh, :auth, :locale]
      upsert? true
      upsert_identity :unique_endpoint
      upsert_fields [:p256dh, :auth, :locale, :user_id, :updated_at]

      validate match(:endpoint, ~r"\Ahttps://")
      validate match(:p256dh, ~r/\A[A-Za-z0-9_-]+\z/)
      validate match(:auth, ~r/\A[A-Za-z0-9_-]+\z/)

      change relate_actor(:user)
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if actor_attribute_equals(:admin, true)
    end

    policy action_type([:read, :destroy]) do
      forbid_unless actor_attribute_equals(:admin, true)
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :endpoint, :string, allow_nil?: false, public?: true
    attribute :p256dh, :string, allow_nil?: false, public?: true
    attribute :auth, :string, allow_nil?: false, public?: true, sensitive?: true
    # The admin's language when they subscribed, which the notifications use.
    attribute :locale, :string, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :user, Edenflowers.Accounts.User, allow_nil?: false
  end

  identities do
    identity :unique_endpoint, [:endpoint]
  end
end
