defmodule Edenflowers.Store.DeliveryAttempt.Outcome do
  use Ash.Type.Enum, values: [:delivered, :failed]
end

defmodule Edenflowers.Store.DeliveryAttempt.DeliveredMethod do
  use Ash.Type.Enum, values: [:handed_to_recipient, :left_in_safe_place, :other]
end

defmodule Edenflowers.Store.DeliveryAttempt.FailureReason do
  use Ash.Type.Enum,
    values: [
      :recipient_unavailable,
      :could_not_access_address,
      :could_not_find_address,
      :recipient_refused,
      :other
    ]
end

defmodule Edenflowers.Store.DeliveryAttempt.ActorKind do
  use Ash.Type.Enum, values: [:driver_link, :admin]
end

defmodule Edenflowers.Store.DeliveryAttempt do
  @moduledoc """
  An append-only record of a delivery attempt against a stop.

  A delivered attempt marks its order fulfilled in the same transaction (handled
  by the outcome-recording orchestration). A failed attempt leaves the order
  pending and preserves its reason, note, and optional proof photo. Later retries
  create additional attempts; attempts are never updated or destroyed.
  """
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Edenflowers.Store.DeliveryAttempt.{ActorKind, DeliveredMethod, FailureReason, Outcome}

  postgres do
    table "delivery_attempts"
    repo Edenflowers.Repo
  end

  code_interface do
    define :get_by_id, action: :by_id, args: [:id]
    define :for_stop, action: :for_stop, args: [:delivery_stop_id]
  end

  actions do
    defaults [
      :read,
      create: [
        :delivery_stop_id,
        :outcome,
        :delivered_method,
        :failure_reason,
        :note,
        :recorded_at,
        :actor_kind,
        :recorded_by_user_id,
        :photo_path,
        :photo_media_type,
        :photo_original_filename,
        :photo_byte_size
      ]
    ]

    read :by_id do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
    end

    read :for_stop do
      argument :delivery_stop_id, :uuid, allow_nil?: false
      filter expr(delivery_stop_id == ^arg(:delivery_stop_id))
      prepare build(sort: [recorded_at: :asc])
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

  validations do
    validate present(:delivered_method),
      where: [attribute_equals(:outcome, :delivered)],
      message: "a delivered attempt requires a method"

    validate present(:failure_reason),
      where: [attribute_equals(:outcome, :failed)],
      message: "a failed attempt requires a reason"

    validate present(:note),
      where: [attribute_equals(:delivered_method, :other)],
      message: "a note is required when the method is other"

    validate present(:note),
      where: [attribute_equals(:failure_reason, :other)],
      message: "a note is required when the reason is other"

    validate present(:recorded_by_user_id),
      where: [attribute_equals(:actor_kind, :admin)],
      message: "an admin-entered attempt must record the acting admin"
  end

  attributes do
    uuid_primary_key :id

    attribute :outcome, Outcome, allow_nil?: false
    attribute :delivered_method, DeliveredMethod
    attribute :failure_reason, FailureReason
    attribute :note, :string

    attribute :recorded_at, :utc_datetime, allow_nil?: false
    attribute :actor_kind, ActorKind, allow_nil?: false

    # Proof photo: the original is written to a persistent volume and only its
    # relative path and metadata are stored here.
    attribute :photo_path, :string
    attribute :photo_media_type, :string
    attribute :photo_original_filename, :string
    attribute :photo_byte_size, :integer

    timestamps()
  end

  relationships do
    belongs_to :delivery_stop, Edenflowers.Store.DeliveryStop, allow_nil?: false

    belongs_to :recorded_by, Edenflowers.Accounts.User do
      source_attribute :recorded_by_user_id
    end
  end
end
