defmodule Edenflowers.Store.ProductVariant do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "product_variants"
    repo Edenflowers.Repo
  end

  code_interface do
    define :get_by_id, action: :get_by_id, args: [:id]
  end

  actions do
    defaults [:read, :destroy]

    read :get_by_id do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
    end

    create :create do
      accept [:price, :size, :image_slug, :stock_trackable, :stock_quantity, :product_id, :draft]
    end

    update :update do
      accept [:price, :size, :image_slug, :stock_trackable, :stock_quantity, :draft]
    end
  end

  policies do
    # Admin bypass - admins can do anything
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Public read access
    policy action_type(:read) do
      authorize_if always()
    end
  end

  preparations do
    prepare build(sort: [price: :asc])
  end

  attributes do
    uuid_primary_key :id
    attribute :price, :decimal, allow_nil?: false
    attribute :size, Edenflowers.Store.ProductVariantSize
    attribute :image_slug, :string, allow_nil?: false
    attribute :stock_trackable, :boolean, default: false
    attribute :stock_quantity, :integer, constraints: [min: 0]
    attribute :draft, :boolean, allow_nil?: false, default: true
  end

  relationships do
    belongs_to :product, Edenflowers.Store.Product, allow_nil?: false
  end
end
