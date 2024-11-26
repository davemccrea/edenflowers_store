defmodule Edenflowers.Store.Promotion do
  use Ash.Resource, domain: Edenflowers.Store, data_layer: AshPostgres.DataLayer

  postgres do
    table "promotions"
    repo Edenflowers.Repo
  end

  code_interface do
    define :get_by_code, args: [:code], action: :by_code, get?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :code, :discount_percentage, :minimum_cart_total, :start_date, :expiration_date]
    end

    read :by_code do
      argument :code, :string, allow_nil?: false

      argument :today, :date,
        default:
          "Europe/Helsinki"
          |> DateTime.now!()
          |> DateTime.to_date()

      filter expr(
               code == ^arg(:code) and ^arg(:today) >= start_date and
                 if(not is_nil(expiration_date), do: ^arg(:today) <= expiration_date, else: true)
             )
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
  end

  identities do
    identity :unique_code, :code
  end
end
