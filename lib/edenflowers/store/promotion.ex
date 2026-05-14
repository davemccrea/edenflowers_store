defmodule Edenflowers.Store.Promotion do
  use Ash.Resource,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "promotions"
    repo Edenflowers.Repo
  end

  code_interface do
    define :get_by_id, args: [:id], action: :by_id, get?: true
    define :get_by_code, args: [:code, {:optional, :today}], action: :by_code, get?: true
    define :increment_usage, action: :increment_usage
    define :create_for_newsletter, action: :create_for_newsletter
  end

  actions do
    defaults [:read, :destroy]

    read :by_id do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
    end

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
      change {Edenflowers.Store.Promotion.Changes.SetNewsletterDefaults, []}
    end

    create :create do
      accept [:name, :code, :discount_percentage, :minimum_cart_total, :start_date, :expiration_date, :usage_limit]
    end

    update :increment_usage do
      change increment(:usage)
    end
  end

  policies do
    # System bypass is scoped to the actions our jobs/webhooks actually invoke.
    bypass actor_attribute_equals(:system, true) do
      authorize_if action([:increment_usage, :create_for_newsletter])
      authorize_if action_type(:read)
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Public read access (for promotion code validation)
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      description "All mutations require admin actor (covered by bypass above)."
      forbid_if always()
    end
  end

  validations do
    validate compare(:discount_percentage, greater_than: 0)
    validate compare(:discount_percentage, less_than_or_equal_to: 1)
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false

    attribute :code, :ci_string do
      allow_nil? false
      constraints allow_empty?: false, trim?: true
    end

    attribute :discount_percentage, :decimal, allow_nil?: false
    attribute :minimum_cart_total, :decimal, allow_nil?: false
    attribute :start_date, :date
    attribute :expiration_date, :date
    attribute :usage, :integer, allow_nil?: false, default: 0
    attribute :usage_limit, :integer, allow_nil?: true
  end

  identities do
    identity :unique_code, [:code]
  end
end
