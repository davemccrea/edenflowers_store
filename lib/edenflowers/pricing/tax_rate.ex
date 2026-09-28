defmodule Edenflowers.Pricing.TaxRate do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Pricing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "tax_rates"
    repo Edenflowers.Repo
  end

  actions do
    # Orders and bookings snapshot the percentage they charged, so editing it
    # (e.g. a statutory VAT change) only affects what is sold from now on.
    # Destroy is refused by the foreign keys while anything still uses the rate.
    defaults [:read, :destroy, create: [:name, :percentage], update: [:name, :percentage]]

    read :selectable do
      filter expr(is_nil(retired_at))
      prepare build(sort: [name: :asc])
    end

    # Hides a rate from the admin forms while what already uses it keeps it.
    update :retire do
      change set_attribute(:retired_at, &DateTime.utc_now/0)
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      description "All mutations require admin actor (covered by bypass above)."
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :percentage, :decimal, allow_nil?: false, constraints: [min: 0, max: 1]
    attribute :retired_at, :utc_datetime_usec
  end

  relationships do
    has_many :products, Edenflowers.Catalog.Product
  end

  identities do
    identity :unique_name, [:name]
  end
end
