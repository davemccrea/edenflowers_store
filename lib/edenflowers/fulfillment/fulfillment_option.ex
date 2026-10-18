defmodule Edenflowers.Fulfillment.FulfillmentOption.RateType do
  use Ash.Type.Enum, values: [:fixed, :dynamic]
end

defmodule Edenflowers.Fulfillment.FulfillmentOption.FulfillmentMethod do
  use Ash.Type.Enum, values: [:delivery, :pickup]
end

defmodule Edenflowers.Fulfillment.FulfillmentOption do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Fulfillment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTranslation.Resource]

  alias Edenflowers.Fulfillment.Actions

  postgres do
    table "fulfillment_options"
    repo Edenflowers.Repo
    migration_types base_price: :decimal, price_per_km: :decimal

    check_constraints do
      check_constraint :base_price, "fulfillment_options_valid_base_price",
        check: "base_price >= 0 AND base_price = round(base_price, 2)",
        message: "must be a non-negative amount in whole cents"

      check_constraint :price_per_km, "fulfillment_options_valid_price_per_km",
        check: "price_per_km >= 0 AND price_per_km = round(price_per_km, 2)",
        message: "must be a non-negative amount in whole cents"
    end
  end

  translations do
    locales Edenflowers.Locales.translatable_atoms()
    fields [:name]
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :name,
        :sort_key,
        :fulfillment_method,
        :rate_type,
        :base_price,
        :price_per_km,
        :free_dist_km,
        :max_dist_km,
        :tax_rate_id,
        :translations
      ],
      update: [
        :name,
        :sort_key,
        :fulfillment_method,
        :rate_type,
        :base_price,
        :price_per_km,
        :free_dist_km,
        :max_dist_km,
        :tax_rate_id,
        :translations
      ]
    ]

    read :list_for_checkout do
      prepare build(sort: [sort_key: :asc, name: :asc])
    end

    update :update_pricing do
      description "Admin-only update narrowed to prices and distances. " <>
                    "Prevents accidental writes to the fulfillment method or rate type."

      accept [:base_price, :price_per_km, :free_dist_km, :max_dist_km]
    end

    action :calculate_delivery, :map do
      argument :delivery_address, :string, allow_nil?: false
      argument :fulfillment_option_id, :uuid, allow_nil?: false
      run Actions.CalculateDelivery
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:action) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      description "All mutations require admin actor (covered by bypass above)."
      forbid_if always()
    end
  end

  validations do
    validate present([:price_per_km, :free_dist_km, :max_dist_km]) do
      where attribute_equals(:rate_type, :dynamic)
    end

    validate compare(:free_dist_km, less_than_or_equal_to: :max_dist_km) do
      where attribute_equals(:rate_type, :dynamic)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :sort_key, :integer, default: 0, allow_nil?: false, public?: true

    attribute :fulfillment_method, __MODULE__.FulfillmentMethod,
      allow_nil?: false,
      public?: true

    attribute :rate_type, __MODULE__.RateType, allow_nil?: false, public?: true
    attribute :base_price, :decimal, allow_nil?: false, public?: true, constraints: [min: 0, scale: 2]
    attribute :price_per_km, :decimal, public?: true, constraints: [min: 0, scale: 2]
    attribute :free_dist_km, :integer, public?: true, constraints: [min: 0]
    attribute :max_dist_km, :integer, public?: true, constraints: [min: 1]
  end

  relationships do
    belongs_to :tax_rate, Edenflowers.Pricing.TaxRate, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_name, [:name]
  end
end
