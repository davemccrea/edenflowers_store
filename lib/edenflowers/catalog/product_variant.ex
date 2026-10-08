defmodule Edenflowers.Catalog.ProductVariant do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshArchival.Resource]

  postgres do
    table "product_variants"
    repo Edenflowers.Repo
    base_filter_sql "(archived_at IS NULL)"

    # The generator would carry `scale: 2` into the migration, which Ecto
    # rejects without a precision. Ash still validates the scale; the check
    # constraint enforces cents at the database.
    migration_types price: :decimal

    check_constraints do
      check_constraint :price, "product_variants_valid_price",
        check: "price >= 0 AND price = round(price, 2)",
        message: "must be a non-negative amount in whole cents"
    end
  end

  # Removing a size archives it: past orders still reference it. The base
  # filter (rather than a read-action filter) also hides archived sizes from
  # relationship expressions like the store's `exists(product_variants)` and
  # the `cheapest_price` aggregate.
  resource do
    base_filter expr(is_nil(archived_at))
  end

  archive do
    base_filter? true
  end

  actions do
    defaults [
      :read,
      create: [:price, :size, :image_slug, :stock_trackable, :stock_quantity, :product_id, :draft],
      update: [:price, :size, :image_slug, :stock_trackable, :stock_quantity, :draft]
    ]

    destroy :destroy do
      primary? true
      require_atomic? false

      validate {Edenflowers.Orders.Validations.NotReferencedByCurrentSubscription,
                reference: :product_variant, field: :id}
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
    attribute :price, :decimal, allow_nil?: false, constraints: [min: 0, scale: 2]
    attribute :size, Edenflowers.Catalog.ProductVariantSize
    attribute :image_slug, :string, allow_nil?: false
    attribute :stock_trackable, :boolean, allow_nil?: false, default: false
    attribute :stock_quantity, :integer, constraints: [min: 0]
    attribute :draft, :boolean, allow_nil?: false, default: true
  end

  relationships do
    belongs_to :product, Edenflowers.Catalog.Product, allow_nil?: false
  end
end
