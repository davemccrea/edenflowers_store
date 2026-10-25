defmodule Edenflowers.Catalog.ProductVariant do
  @moduledoc """
  A product size with its own price, optional photo, and optional tracked stock. Removed sizes are archived so past order lines keep their reference.
  """

  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshArchival.Resource],
    notifiers: [Ash.Notifier.PubSub]

  require Ash.Sort

  alias Edenflowers.Orders.Validations

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
      create: [
        :price,
        :size,
        :height_cm,
        :stem_count,
        :dimensions_cm,
        :pot_cm,
        :weight_g,
        :pieces,
        :own_photo_slug,
        :stock_quantity,
        :product_id,
        :draft
      ],
      update: [
        :price,
        :size,
        :height_cm,
        :stem_count,
        :dimensions_cm,
        :pot_cm,
        :weight_g,
        :pieces,
        :own_photo_slug,
        :stock_quantity,
        :draft
      ]
    ]

    # Stock never goes below 0; see Orders.Changes.AdjustStock.
    update :adjust_stock do
      argument :by, :integer, allow_nil?: false

      change atomic_update(
               :stock_quantity,
               expr(if(stock_quantity + ^arg(:by) < 0, 0, stock_quantity + ^arg(:by)))
             )
    end

    destroy :destroy do
      primary? true
      require_atomic? false

      validate {Validations.NotReferencedByCurrentSubscription, reference: :product_variant, field: :id}
    end

    # Sizes on sale that have run out, for the Overview. Cards count, as checkout offers them.
    read :sold_out do
      filter expr(
               stock_quantity == 0 and draft == false and product.draft == false and
                 product.product_category.visibility != :draft
             )

      prepare build(sort: [size: :asc], load: [:product])
    end

    read :for_card_drawer do
      # Cards are hidden from the storefront and offered only at checkout.
      filter expr(
               draft == false and
                 (is_nil(stock_quantity) or stock_quantity > 0) and
                 product.draft == false and
                 product.product_category.slug == "cards" and
                 product.product_category.visibility != :draft
             )

      prepare build(load: [:photo_slug, product: [:tax_rate]])
    end

    # Cards are added through the card drawer. Draft and sold-out sizes stay, as
    # a custom order can be priced for anything the shop can make.
    read :for_custom_order do
      filter expr(product.product_category.slug != "cards")
      prepare build(load: [:product])

      # Ahead of the resource's own price sort, so each product's sizes stay together.
      prepare fn query, _context ->
        Ash.Query.sort(query, [{Ash.Sort.expr_sort(product.name, :string), :asc}], prepend?: true)
      end
    end

    # The sizes a subscription can switch to. Its current size stays on offer
    # even once it's a draft, so the customer can keep it.
    read :subscription_sizes do
      argument :current_variant_id, :uuid, allow_nil?: false

      filter expr(
               exists(product.product_variants, id == ^arg(:current_variant_id)) and
                 (draft == false or id == ^arg(:current_variant_id))
             )
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

  # Product pages listen so a size that sells out elsewhere shows as sold out.
  pub_sub do
    module EdenflowersWeb.Endpoint

    publish :adjust_stock, ["product_variant", "changed", :product_id]
    publish :update, ["product_variant", "changed", :product_id]
  end

  preparations do
    prepare build(sort: [price: :asc])
  end

  attributes do
    uuid_primary_key :id
    attribute :price, :decimal, allow_nil?: false, constraints: [min: 0, scale: 2]
    attribute :size, Edenflowers.Catalog.ProductVariantSize
    # Display text such as "30–40", so a range or a single value both fit. The category's
    # product type says which of these its sizes have; see ProductType.
    attribute :height_cm, :string
    attribute :stem_count, :string
    attribute :dimensions_cm, :string
    attribute :pot_cm, :string
    attribute :weight_g, :string
    attribute :pieces, :string
    # One of the product's photos, or nil to show its main photo; see `photo_slug`.
    attribute :own_photo_slug, :string
    # Nil for a size made to order, which never runs out.
    attribute :stock_quantity, :integer, constraints: [min: 0]
    attribute :draft, :boolean, allow_nil?: false, default: true
  end

  relationships do
    belongs_to :product, Edenflowers.Catalog.Product, allow_nil?: false
  end

  calculations do
    calculate :photo_slug, :string, expr(own_photo_slug || product.main_photo_slug)
  end
end
