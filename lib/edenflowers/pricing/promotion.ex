defmodule Edenflowers.Pricing.Promotion do
  use Ash.Resource,
    domain: Edenflowers.Pricing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "promotions"
    repo Edenflowers.Repo
    migration_types minimum_cart_total: :decimal

    check_constraints do
      check_constraint :minimum_cart_total, "promotions_valid_minimum_cart_total",
        check: "minimum_cart_total >= 0 AND minimum_cart_total = round(minimum_cart_total, 2)",
        message: "must be a non-negative amount in whole cents"
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:name, :code, :discount_rate, :minimum_cart_total, :start_date, :expiration_date, :usage_limit]
    ]

    read :by_code do
      argument :code, :string, allow_nil?: false

      argument :today, :date, default: fn -> "Europe/Helsinki" |> DateTime.now!() |> DateTime.to_date() end

      filter expr(
               code == ^arg(:code) and
                 (is_nil(usage_limit) or usage < usage_limit) and
                 (is_nil(start_date) or ^arg(:today) >= start_date) and
                 (is_nil(expiration_date) or ^arg(:today) <= expiration_date)
             )
    end

    create :create_for_newsletter do
      change Edenflowers.Pricing.Promotion.Changes.SetNewsletterDefaults
    end
  end

  policies do
    # System bypass is scoped to the actions our jobs/webhooks actually invoke.
    bypass actor_attribute_equals(:system, true) do
      authorize_if action(:create_for_newsletter)
      authorize_if action_type(:read)
    end

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

  validations do
    validate compare(:discount_rate, greater_than: 0)
    validate compare(:discount_rate, less_than_or_equal_to: 1)
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false

    attribute :code, :ci_string do
      allow_nil? false
      constraints allow_empty?: false, trim?: true
    end

    attribute :discount_rate, :decimal, allow_nil?: false
    attribute :minimum_cart_total, :decimal, allow_nil?: false, constraints: [min: 0, scale: 2]
    attribute :start_date, :date
    attribute :expiration_date, :date
    attribute :usage_limit, :integer, allow_nil?: true
  end

  relationships do
    has_many :orders, Edenflowers.Orders.Order
  end

  aggregates do
    # Unauthorized so a guest checking a code still counts everyone's orders.
    count :usage, :orders do
      filter expr(state == :placed)
      authorize? false
    end
  end

  identities do
    identity :unique_code, [:code]
  end
end
