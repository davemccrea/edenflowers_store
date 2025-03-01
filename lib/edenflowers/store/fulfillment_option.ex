defmodule Edenflowers.Store.FulfillmentOption.RateType do
  use Ash.Type.Enum, values: [:fixed, :dynamic]
end

defmodule Edenflowers.Store.FulfillmentOption.FulfillmentMethod do
  use Ash.Type.Enum, values: [:delivery, :pickup]
end

defmodule Edenflowers.Store.FulfillmentOption do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTrans.Resource]

  postgres do
    table "fulfillment_options"
    repo Edenflowers.Repo
  end

  # TODO: test translations
  translations do
    public? true
    fields [:name]
    locales [:sv, :fi]
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  validations do
    validate present([:price_per_km, :free_dist_km, :max_dist_km]) do
      where attribute_equals(:rate_type, :dynamic)
    end

    validate present(:order_deadline) do
      where attribute_equals(:same_day, true)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true

    attribute :minimum_cart_total, :decimal, default: 0, public?: true

    attribute :fulfillment_method, Edenflowers.Store.FulfillmentOption.FulfillmentMethod,
      allow_nil?: false,
      public?: true

    attribute :rate_type, Edenflowers.Store.FulfillmentOption.RateType, allow_nil?: false, public?: true
    attribute :base_price, :decimal, allow_nil?: false, public?: true
    attribute :price_per_km, :decimal, public?: true
    attribute :free_dist_km, :integer, public?: true
    attribute :max_dist_km, :integer, public?: true

    attribute :same_day, :boolean, default: false, public?: true
    attribute :order_deadline, :time, default: ~T[14:00:00], public?: true

    attribute :monday, :boolean, default: true, public?: true
    attribute :tuesday, :boolean, default: true, public?: true
    attribute :wednesday, :boolean, default: true, public?: true
    attribute :thursday, :boolean, default: true, public?: true
    attribute :friday, :boolean, default: true, public?: true
    attribute :saturday, :boolean, default: true, public?: true
    attribute :sunday, :boolean, default: false, public?: true

    attribute :enabled_dates, {:array, :date}, default: [], public?: true
    attribute :disabled_dates, {:array, :date}, default: [], public?: true
  end

  relationships do
    belongs_to :tax_rate, Edenflowers.Store.TaxRate, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_name, [:name]
  end
end
