defmodule Edenflowers.Fulfillment.FulfillmentOption.RateType do
  @moduledoc """
  Whether a fulfillment fee is fixed or varies with delivery distance.
  """

  use Ash.Type.Enum, values: [:fixed, :dynamic]
end

defmodule Edenflowers.Fulfillment.FulfillmentOption.FulfillmentMethod do
  @moduledoc """
  The delivery and pickup methods supported at checkout.
  """

  use Ash.Type.Enum, values: [:delivery, :pickup]
end

defmodule Edenflowers.Fulfillment.FulfillmentOption do
  @moduledoc """
  A delivery or pickup choice with its customer-facing name, fee rules, VAT rate, and delivery range. Checkout snapshots selected terms onto the order.
  """

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
      description "Every option, in the order checkout shows them."
      prepare build(sort: [sort_key: :asc, name: :asc])
    end

    update :update_pricing do
      description "Admin-only update narrowed to prices, distances and running costs. " <>
                    "Prevents accidental writes to the fulfillment method or rate type."

      accept [
        :base_price,
        :price_per_km,
        :free_dist_km,
        :max_dist_km,
        :mileage_rate,
        :fuel_price,
        :fuel_consumption
      ]
    end

    action :calculate_delivery, :map do
      description "Geocodes a delivery address with HERE and prices it with the option's fee rules. An " <>
                    "undeliverable address is returned as `%{error: reason}` rather than failing."

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

    attribute :name, :string do
      description "What checkout calls the option, translated."
      allow_nil? false
      public? true
    end

    attribute :sort_key, :integer do
      description "Checkout lists options by this, lowest first, then by name."
      default 0
      allow_nil? false
      public? true
    end

    attribute :fulfillment_method, __MODULE__.FulfillmentMethod do
      description "Delivery to the Recipient's address, or pickup from the shop. Pickup has no distance to price."
      allow_nil? false
      public? true
    end

    attribute :rate_type, __MODULE__.RateType do
      description ":fixed charges `base_price` wherever it goes. :dynamic adds `price_per_km` for the driving " <>
                    "distance from the shop, up to `max_dist_km`."

      allow_nil? false
      public? true
    end

    attribute :base_price, :decimal do
      description "The fee in euros, VAT included. For a :dynamic option, the starting fee before distance is added."
      allow_nil? false
      public? true
      constraints min: 0, scale: 2
    end

    attribute :price_per_km, :decimal do
      description "Euros per km of driving distance from the shop, VAT included. Required for a :dynamic option."
      public? true
      constraints min: 0, scale: 2
    end

    attribute :free_dist_km, :integer do
      description "Within this many km the fee is waived for an order holding a free-delivery product. Only " <>
                    "a :dynamic option uses it, and it is required there."

      public? true
      constraints min: 0
    end

    attribute :max_dist_km, :integer do
      description "The furthest it delivers, in km of driving distance; addresses this far or further are out of " <>
                    "range. Only a :dynamic option uses it, and it is required there."

      public? true
      constraints min: 1
    end

    # What a delivery costs Jennie, shown in admin beside the fee and never charged.
    attribute :mileage_rate, :decimal, public?: true, constraints: [min: 0], description: "Kilometrikorvaus, € per km"
    attribute :fuel_price, :decimal, public?: true, constraints: [min: 0], description: "€ per litre"
    attribute :fuel_consumption, :decimal, public?: true, constraints: [min: 0], description: "Litres per 100 km"
  end

  relationships do
    belongs_to :tax_rate, Edenflowers.Pricing.TaxRate do
      description "The VAT rate the fee includes. Orders snapshot the percentage at checkout."
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_name, [:name]
  end
end
