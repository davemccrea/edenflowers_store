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
    define :get_by_id, args: [:id], action: :get_by_id, get?: true
    define :get_by_code, args: [:code], action: :get_by_code, get?: true
    define :increment_usage, action: :increment_usage
  end

  actions do
    defaults [:read, :destroy]

    read :get_by_id do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
    end

    read :get_by_code do
      argument :code, :string, allow_nil?: false

      argument :today, :date,
        default:
          "Europe/Helsinki"
          |> DateTime.now!()
          |> DateTime.to_date()

      filter expr(
               code == ^arg(:code) and
                 if(not is_nil(usage_limit), do: usage < usage_limit, else: true) and
                 if(not is_nil(start_date), do: ^arg(:today) >= start_date, else: true) and
                 if(not is_nil(expiration_date), do: ^arg(:today) <= expiration_date, else: true)
             )
    end

    create :create_for_newsletter do
      # TODO: generate a promotion with random code
    end

    create :create do
      accept [:name, :code, :discount_percentage, :minimum_cart_total, :start_date, :expiration_date]
    end

    update :increment_usage do
      change increment(:usage)
    end
  end

  policies do
    # System bypass - for webhooks and background jobs
    bypass actor_attribute_equals(:system, true) do
      authorize_if always()
    end

    # Admin bypass - admins can do anything
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Public read access (for promotion code validation)
    policy action_type(:read) do
      authorize_if always()
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
    identity :unique_code, :code
  end
end
