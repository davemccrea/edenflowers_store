defmodule Edenflowers.Pricing.TaxRate do
  @moduledoc """
  A VAT rate assigned to products, courses, or fulfillment fees.
  """

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
      description "Rates an admin form can pick, highest first so the standard rate is what the select starts on. " <>
                    "Retired rates are left out unless `percentages` names one."

      argument :percentages, {:array, :decimal} do
        default []
        description "Retired rates the record being edited already charges, kept selectable so editing it keeps them."
      end

      filter expr(is_nil(retired_at) or percentage in ^arg(:percentages))
      prepare build(sort: [retired_at: :asc_nils_first, percentage: :desc])
    end

    update :retire do
      description "Hides a rate from the admin forms while what already uses it keeps it."
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

    attribute :percentage, :decimal do
      description "The VAT rate as a fraction, so 0.14 is 14%."
      allow_nil? false
      constraints min: 0, max: 1
    end

    attribute :retired_at, :utc_datetime_usec
  end

  relationships do
    has_many :products, Edenflowers.Catalog.Product do
      description "Products whose prices include this rate. Courses and fulfillment options use rates too."
    end
  end

  identities do
    identity :unique_name, [:name]
  end
end
