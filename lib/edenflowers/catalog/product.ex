defmodule Edenflowers.Catalog.Product do
  @moduledoc """
  A sellable product with translated copy, photos, category, and one or more
  priced sizes. Store reads exclude drafts and nonpublic categories; stock is
  tracked on individual variants when applicable.
  """

  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshTranslation.Resource]

  alias Edenflowers.Catalog.Changes
  alias Edenflowers.Catalog.Preparations
  alias Edenflowers.Catalog.Validations
  alias Edenflowers.Events

  @slug_options [former_slugs: Edenflowers.Catalog.FormerProductSlug, owner_key: :product_id, fallback: "product"]

  # More cards than this fan out too thinly to tap on a phone.
  @max_fan_cards 7
  def max_fan_cards, do: @max_fan_cards

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false

    attribute :slug, :string do
      description "Where the product's page lives, as in /product/red-rose-bouquet. Made from the English name " <>
                    "when the product is created and kept when it is renamed; Jennie can edit it in the product " <>
                    "form."

      allow_nil? false
      public? true
    end

    attribute :photo_slugs, {:array, :string} do
      description "In display order; the first is the main photo, see `main_photo_slug`."
      allow_nil? false
      constraints min_length: 1, max_length: 8
    end

    attribute :hidden_photo_slugs, {:array, :string} do
      description "Left out of the store's gallery but still pickable by a size. Never the main photo."
      allow_nil? false
      default []
    end

    attribute :description, :string, allow_nil?: false
    attribute :draft, :boolean, allow_nil?: false, default: true
    attribute :featured, :boolean, allow_nil?: false, default: false

    attribute :position, :integer do
      description "Store order within a category: 0 first, unset after all positioned products."
      constraints min: 0
    end

    attribute :free_delivery, :boolean do
      description "A cart holding it pays the option's free-delivery fee: nothing within its free distance, " <>
                    "and only the distance beyond it otherwise (Fulfillment.Fee)."

      allow_nil? false
      default false
    end

    attribute :subscribable, :boolean do
      description "Can also be bought as a Subscription, which the customer opts into on the product page. " <>
                    "Bought once, it is like any other product."

      allow_nil? false
      default false
    end

    attribute :bow_colours, {:array, Edenflowers.Catalog.BowColour} do
      description "The bows a customer can choose from on its page. Empty when it asks for none, as most " <>
                    "products do."

      allow_nil? false
      default []
      # The admin form posts a blank entry so unticking every colour still sends the field.
      constraints remove_nil_items?: true
    end

    attribute :available_from, :date do
      description "Its Available from: the first day Jennie can make it again once she has run out of its " <>
                    "flowers, after the next flower delivery. Nil, or a day already past, when it can be made now. " <>
                    "Customers can still order it, for that day or later."
    end
  end

  relationships do
    belongs_to :tax_rate, Edenflowers.Pricing.TaxRate do
      description "The VAT rate its prices include. Orders snapshot the percentage, so changing it only affects " <>
                    "what is sold from now on."

      allow_nil? false
    end

    belongs_to :product_category, Edenflowers.Catalog.ProductCategory do
      description "Its category, whose visibility decides whether the store shows it and whose `add_on` flag " <>
                    "decides whether it's an Add-on."

      allow_nil? false
    end

    has_many :former_slugs, Edenflowers.Catalog.FormerProductSlug do
      description "Slugs the product used to have. Links with them redirect to its current slug."
    end

    has_many :product_variants, Edenflowers.Catalog.ProductVariant do
      description "Its sizes, each with its own price and Stock, cheapest first. Archived sizes are left out."
    end
  end

  calculations do
    calculate :matches?,
              :boolean,
              expr(
                contains(name, ^arg(:term)) or contains(translations[:"sv-FI"][:name], ^arg(:term)) or
                  contains(translations[:fi][:name], ^arg(:term))
              ) do
      description "The admin products search, case-insensitive: whether the term appears in the name in any language."
      argument :term, :ci_string, allow_nil?: false
    end

    calculate :main_photo_slug, :string, expr(at(photo_slugs, 0)) do
      description "The first of `photo_slugs`, shown on store cards and for sizes without their own photo."
    end

    calculate :pictured_sizes, :map, Edenflowers.Catalog.Calculations.PicturedSizes do
      description "Which size each photo shows, keyed by photo slug: a size's own photo shows that size, and the " <>
                    "main photo shows Medium when the product has one. Photos of unknown size are left out. The " <>
                    "product page uses it to say when the photo isn't the chosen size."
    end

    calculate :sold_out?,
              :boolean,
              expr(
                exists(product_variants) and
                  not exists(product_variants, is_nil(stock_quantity) or stock_quantity > 0)
              ) do
      description "Every size has run out of Stock. Never true for a product with a made-to-order size, " <>
                    "or with no sizes at all."
    end

    calculate :waiting_until, :date, expr(if(available_from > helsinki_today(), do: available_from, else: nil)) do
      description "Its Available from while that day is still ahead, else nil. The store shows it as " <>
                    "\"Available from\" in place of Sold out."
    end

    calculate :first_open_day,
              :date,
              {Edenflowers.Fulfillment.Calculations.FirstOpenDay, from: :waiting_until} do
      description "The first day on or after its Available from that the shop calendar is open, else nil. " <>
                    "The store names this day as \"Available from\", so it never names a day Jennie has closed."
    end
  end

  aggregates do
    min :cheapest_price, :product_variants, :price do
      description "The lowest size price in euros, VAT included, shown as \"from\". Nil for a product without sizes."
    end
  end

  identities do
    identity :unique_name, [:name]
    identity :unique_slug, [:slug]
  end

  actions do
    defaults [:read, :destroy]

    read :for_product_page do
      description "A product with everything its page shows (sizes, category and photos) plus its tax rate. " <>
                    "Unlike the store reads, drafts are not filtered out."

      prepare build(
                load: [
                  :main_photo_slug,
                  :pictured_sizes,
                  :product_category,
                  :tax_rate,
                  :waiting_until,
                  :first_open_day,
                  product_variants: [:photo_slug]
                ]
              )
    end

    action :current_slug, :string do
      allow_nil? true

      description "Where an outdated product link should go: the current slug of the product whose id or " <>
                    "former slug `param` is, or nil when `param` is neither, such as a current slug. Product " <>
                    "pages redirect old links with it."

      argument :param, :string do
        description "The last part of a product URL."
        allow_nil? false
      end

      run {Edenflowers.Slug.CurrentSlug, @slug_options}
    end

    read :for_store do
      description "Every product the store shows: published, in a public category, with at least one size. Sold-out " <>
                    "products are included and marked by `sold_out?`."

      prepare Preparations.VisibleInStore
    end

    read :featured do
      description "Featured products for the home page, in store order. Only products the store shows, as in " <>
                    "`for_store`."

      filter expr(featured == true)
      prepare Preparations.VisibleInStore
      prepare build(sort: [position: :asc_nils_last, name: :asc], load: [:product_category])
    end

    read :featured_cards do
      description "Cards Jennie has ticked Favourite, for the fan on the home page, in store order and no more than " <>
                    "the fan holds. Cards are hidden from the storefront, so this offers the same published, " <>
                    "in-stock cards as ProductVariant's `for_card_drawer`."

      filter expr(
               featured == true and
                 draft == false and
                 product_category.slug == "cards" and
                 product_category.visibility != :draft and
                 exists(product_variants, draft == false and (is_nil(stock_quantity) or stock_quantity > 0))
             )

      prepare build(sort: [position: :asc_nils_last, name: :asc], load: [:main_photo_slug], limit: @max_fan_cards)
    end

    # Categories are data, so the bouquet category is found by its English slug.
    read :bouquets do
      description "Products in the bouquets category that the store shows, as in `for_store`."
      filter expr(product_category.slug == "bouquets")
      prepare Preparations.VisibleInStore
    end

    read :subscribable do
      description "Products that can be bought as a Subscription, in store order. Only products the store shows, as " <>
                    "in `for_store`."

      filter expr(subscribable == true)
      prepare Preparations.VisibleInStore
      prepare build(sort: [position: :asc_nils_last, name: :asc])
    end

    read :by_category do
      description "A category's products in store order. Only products the store shows, as in `for_store`."
      argument :category_id, :uuid, allow_nil?: false

      filter expr(product_category_id == ^arg(:category_id))
      prepare Preparations.VisibleInStore
      prepare build(sort: [position: :asc_nils_last, name: :asc])
    end

    create :create do
      description "Creates a product from the admin form, with its sizes given as `product_variants`."

      # SetSlug makes one from the name when the form leaves it blank.
      allow_nil_input [:slug]

      accept [
        :name,
        :photo_slugs,
        :hidden_photo_slugs,
        :description,
        :tax_rate_id,
        :product_category_id,
        :draft,
        :featured,
        :position,
        :free_delivery,
        :subscribable,
        :bow_colours,
        :available_from,
        :translations,
        :slug
      ]

      argument :product_variants, {:array, :map}

      validate Validations.SizePhotosAreProducts
      change Changes.FitWreathChoices

      change {Edenflowers.Slug.SetSlug, @slug_options}
      change Changes.TidyHiddenPhotos

      change manage_relationship(:product_variants,
               type: :direct_control,
               on_no_match: {:create, :create},
               on_match: {:update, :update},
               on_missing: :ignore
             )
    end

    update :update do
      description "Saves the admin product form. Sizes left out of `product_variants` are archived, and a product " <>
                    "can't stop being subscribable or free delivery while a current Subscription relies on it."

      accept [
        :name,
        :photo_slugs,
        :hidden_photo_slugs,
        :description,
        :tax_rate_id,
        :product_category_id,
        :draft,
        :featured,
        :position,
        :free_delivery,
        :subscribable,
        :bow_colours,
        :available_from,
        :translations,
        :slug
      ]

      argument :product_variants, {:array, :map}
      require_atomic? false

      validate Validations.SizePhotosAreProducts
      change Changes.FitWreathChoices

      validate {Edenflowers.Orders.Validations.NotReferencedByCurrentSubscription,
                reference: :product, field: :subscribable, changing_to: {:subscribable, false}}

      validate {Edenflowers.Orders.Validations.NotReferencedByCurrentSubscription,
                reference: :product, field: :free_delivery, changing_to: {:free_delivery, false}}

      # A size left out of the form was removed; destroying archives it.
      change manage_relationship(:product_variants,
               type: :direct_control,
               on_no_match: {:create, :create},
               on_match: {:update, :update},
               on_missing: {:destroy, :destroy}
             )

      change {Edenflowers.Slug.SetSlug, @slug_options}
      change Changes.TidyHiddenPhotos
      change Changes.ClearRemovedSizePhotos
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:current_slug) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      description "All mutations require admin actor (covered by bypass above)."
      forbid_if always()
    end
  end

  # The admin's product list follows catalogue changes; size changes publish
  # through ProductVariant to the same topic.
  pub_sub do
    module EdenflowersWeb.Endpoint

    publish_all :create, Events.admin_products()
    publish_all :update, Events.admin_products()
    publish_all :destroy, Events.admin_products()

    publish_all :create, Events.admin_product(:id)
    publish_all :update, Events.admin_product(:id)
    publish_all :destroy, Events.admin_product(:id)
  end

  translations do
    locales Edenflowers.Locales.translatable_atoms()
    fields [:name, :description]
  end

  postgres do
    table "products"
    repo Edenflowers.Repo
  end
end

defimpl Phoenix.Param, for: Edenflowers.Catalog.Product do
  def to_param(product), do: product.slug
end
