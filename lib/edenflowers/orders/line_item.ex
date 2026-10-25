defmodule Edenflowers.Orders.LineItem.OrderNotPlaced do
  @moduledoc """
  Authorizes a LineItem create only when the target Order is still in checkout.
  Filter-expression checks (`forbid_if expr(order.state == :placed)`) cannot be
  used on creates because there is no row to filter; this check resolves the
  related order at policy-evaluation time instead.
  """
  use Ash.Policy.SimpleCheck

  alias Edenflowers.Orders

  @impl true
  def describe(_opts), do: "order is not in :placed state"

  @impl true
  def match?(_actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    case Ash.Changeset.get_attribute(changeset, :order_id) do
      nil ->
        false

      order_id ->
        case Orders.get_order_by_id(order_id, authorize?: false) do
          {:ok, %{state: :placed}} -> false
          {:ok, _} -> true
          {:error, _} -> false
        end
    end
  end

  def match?(_, _, _), do: false
end

defmodule Edenflowers.Orders.LineItem do
  @moduledoc """
  A cart or order line. Catalogue lines snapshot product details and price; custom-order lines may be described and priced by Jennie.
  """

  use Ash.Resource,
    domain: Edenflowers.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias Edenflowers.Orders.Changes.PopulateFromVariant
  alias Edenflowers.Orders.LineItem.Changes
  alias Edenflowers.Orders.LineItem.Validations

  postgres do
    repo Edenflowers.Repo
    table "line_items"
    migration_types unit_price: :decimal

    check_constraints do
      check_constraint :unit_price, "line_items_valid_unit_price",
        check: "unit_price >= 0 AND unit_price = round(unit_price, 2)",
        message: "must be a non-negative amount in whole cents"

      check_constraint :product_variant_id, "line_items_catalogue_lines_have_a_product",
        check: "(product_variant_id IS NULL) = (product_id IS NULL)",
        message: "must name both the product and its variant, or neither"
    end

    references do
      reference :order, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :add_to_cart do
      description "Puts a size in the customer's cart, merging into its line if there is one, within Stock. " <>
                    "A subscription goes alone: adding one, or beside one, replaces a cart of only that product " <>
                    "and is refused otherwise."

      accept [:order_id, :product_variant_id, :quantity, :is_card, :interval_weeks]

      # KeepSubscriptionAlone replaces or refuses before the upsert can merge a
      # one-off and a subscription of the same variant.
      upsert? true
      upsert_identity :unique_product_variant
      upsert_fields [:quantity]

      validate attribute_in(:interval_weeks, Edenflowers.Orders.Subscription.intervals())
      validate Validations.Subscribable
      validate Validations.WithinStock
      change PopulateFromVariant
      change Changes.KeepSubscriptionAlone
      change atomic_update(:quantity, expr(quantity + ^atomic_ref(:quantity)))
    end

    create :enter do
      description "A line Jennie enters when she places or edits a Custom Order: a size from the catalogue, " <>
                    "priced from it, or an item she describes and prices herself with a VAT rate."

      accept [:product_variant_id, :product_name, :unit_price, :quantity, :is_card]
      # A catalogue line takes them from its variant; a custom one is checked below.
      allow_nil_input [:product_name, :unit_price]
      argument :kind, :atom, allow_nil?: false, constraints: [one_of: [:catalogue, :custom]]
      argument :tax_rate_id, :uuid

      validate present(:product_variant_id), message: "choose a product", where: [argument_equals(:kind, :catalogue)]
      validate present(:product_name), message: "describe the item", where: [argument_equals(:kind, :custom)]
      validate present(:unit_price), message: "enter a price", where: [argument_equals(:kind, :custom)]
      validate present(:tax_rate_id), message: "choose a VAT rate", where: [argument_equals(:kind, :custom)]

      change PopulateFromVariant, where: [argument_equals(:kind, :catalogue)]
      change Changes.SetTaxRate, where: [argument_equals(:kind, :custom)]
    end

    # The destroy notification publishes to the removed item's order_id topic.
    destroy :remove_item do
      description "Removes a line from an order not yet placed, or one Jennie drops when editing an order."
      require_atomic? false
    end

    # A subscription is for one bouquet each time.
    update :increment_quantity do
      description "Adds one to a cart line, within Stock. A subscription line stays at one."
      require_atomic? false
      validate Validations.WithinStock
      change atomic_update(:quantity, expr(if(is_nil(interval_weeks), quantity + 1, quantity)))
    end

    update :decrement_quantity do
      description "Takes one off a cart line, never below one: removing the line is remove_item."
      change atomic_update(:quantity, expr(if(quantity > 1, quantity - 1, quantity)))
    end

    update :set_quantity do
      description "Sets the quantity of a line Jennie keeps when editing an order, unchecked against Stock."
      accept [:quantity]
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if action_type(:read)
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if action_type(:read)
    end

    policy action_type(:read) do
      authorize_if expr(order.state != :placed)
      authorize_if expr(order.state == :placed and order.user_id == ^actor(:id))
    end

    # Filter expressions can't authorize creates (no row to filter yet), so a
    # custom check resolves the parent order's state at evaluation time.
    policy action_type(:create) do
      authorize_if __MODULE__.OrderNotPlaced
    end

    policy action_type([:update, :destroy]) do
      forbid_if expr(order.state == :placed)
      authorize_if always()
    end
  end

  pub_sub do
    module EdenflowersWeb.Endpoint

    publish_all :create, ["line_item", "changed", :order_id]
    publish_all :update, ["line_item", "changed", :order_id]
    publish_all :destroy, ["line_item", "changed", :order_id], previous_values?: true
  end

  preparations do
    prepare build(load: [:subtotal], sort: [inserted_at: :asc])
  end

  attributes do
    uuid_primary_key :id
    attribute :quantity, :integer, allow_nil?: false, default: 1, constraints: [min: 1]
    attribute :unit_price, Edenflowers.Types.Price, allow_nil?: false, constraints: [min: 0, scale: 2]
    attribute :tax_rate, :decimal, allow_nil?: false
    attribute :product_name, :string, allow_nil?: false
    # Nil for a custom item, which has no product photo.
    attribute :product_image_slug, :string
    attribute :is_card, :boolean, default: false, allow_nil?: false
    # Snapshotted from the product, so unflagging it later leaves existing orders' fees alone.
    attribute :free_delivery, :boolean, default: false, allow_nil?: false
    # How often a subscription line is to be delivered, chosen on the product
    # page. Nil for a one-off.
    attribute :interval_weeks, :integer
    attribute :variant_size, Edenflowers.Catalog.ProductVariantSize
    timestamps()
  end

  relationships do
    belongs_to :order, Edenflowers.Orders.Order do
      description "The cart or order the line belongs to; it goes when the order is deleted."
      allow_nil? false
    end

    belongs_to :product, Edenflowers.Catalog.Product do
      description "The catalogue product the line was taken from. Nil for a custom item, as is its variant."
    end

    belongs_to :product_variant, Edenflowers.Catalog.ProductVariant do
      description "The size sold, whose Stock the line takes once placed. Nil for a custom item."
    end
  end

  calculations do
    calculate :promotion_applied?, :boolean, expr(order.promotion_applied?) do
      description "Whether its order's promotion code currently applies, so the line is discounted."
    end

    calculate :subtotal, :decimal, expr(unit_price * quantity) do
      description "Unit price times quantity in euros, VAT included, before any promotion."
    end

    calculate :over_stock?,
              :boolean,
              expr(
                is_nil(interval_weeks) and not is_nil(product_variant.stock_quantity) and
                  quantity > product_variant.stock_quantity
              ) do
      description "Whether the cart asks for more than is in Stock, as others bought it since it went in the " <>
                    "cart. Never for a subscription line, whose bouquets are made fresh."
    end

    calculate :total,
              :decimal,
              expr(
                if(
                  promotion_applied?,
                  do: subtotal - discount,
                  else: subtotal
                )
              ) do
      description "What the line costs in euros, VAT included, after any promotion."
    end

    calculate :discount, :decimal, Edenflowers.Orders.Calculations.LineDiscount do
      description "What the order's promotion takes off the line in euros, rounded to cents line by line; " <>
                    "0 without a promotion."
    end

    calculate :unit_price_ex_tax, :decimal, expr(round(unit_price / (1 + tax_rate), 2)) do
      description "The unit price without VAT in euros, rounded to cents. unit_price is stored VAT-inclusive."
    end
  end

  identities do
    identity :unique_product_variant, [:order_id, :product_variant_id]
  end
end
