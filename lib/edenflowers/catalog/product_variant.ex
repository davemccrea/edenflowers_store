defmodule Edenflowers.Catalog.ProductVariant do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "product_variants"
    repo Edenflowers.Repo
  end

  actions do
    defaults [:read, :destroy]

    read :by_id do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
    end

    read :for_card_drawer do
      # The Cards category is intentionally hidden from the storefront
      # (visibility: :hidden) — products are surfaced only at checkout via
      # this action. Excluding :draft keeps work-in-progress categories out.
      filter expr(
               draft == false and
                 product.draft == false and
                 product.product_category.slug == "cards" and
                 product.product_category.visibility != :draft
             )

      prepare build(sort: [size: :asc], load: [product: [:tax_rate]])
    end

    create :create do
      accept [:price, :size, :image_slug, :stock_trackable, :stock_quantity, :product_id, :draft]
    end

    update :update do
      accept [:price, :size, :image_slug, :stock_trackable, :stock_quantity, :draft]
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

  preparations do
    prepare build(sort: [price: :asc])
  end

  attributes do
    uuid_primary_key :id
    attribute :price, :decimal, allow_nil?: false
    attribute :size, Edenflowers.Catalog.ProductVariantSize
    attribute :image_slug, :string, allow_nil?: false
    attribute :stock_trackable, :boolean, default: false
    attribute :stock_quantity, :integer, constraints: [min: 0]
    attribute :draft, :boolean, allow_nil?: false, default: true
  end

  relationships do
    belongs_to :product, Edenflowers.Catalog.Product, allow_nil?: false
  end
end
