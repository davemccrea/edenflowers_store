defmodule Edenflowers.Repo.Migrations.SplitOrderIntoCartAndOrder do
  @moduledoc """
  Splits the dual-purpose `Order` resource into two tables:

    * `carts` — owns the form-progress state machine and the cart-flow
      fields. Lives behind the browser session cookie.
    * `orders` — immutable post-conversion record. Snapshot of what was
      bought at place-time.

  Plus two new line-item tables:

    * `cart_line_items` — mutable, belongs to a `Cart`.
    * `order_line_items` — immutable, belongs to an `Order`. Includes
      snapshotted `line_total`, `discount_amount`, `line_tax_amount`
      so a later promotion edit can't change history.

  This migration is the schema half of the split. Backfill of any existing
  data — moving in-flight orders into `carts` and snapshotting placed
  orders into the new `orders` shape — is the subject of a follow-up
  migration, intended to ship behind a flag (see ADR-0001 §"PR scoping").

  As a result, this migration drops the legacy `state` column from `orders`
  and drops the legacy `line_items` table. In dev/test that means
  `mix ecto.reset` is required if you have data sitting around. In
  production, do *not* deploy this without first rolling out PR 2.
  """

  use Ecto.Migration

  def up do
    # New table: carts
    create table(:carts, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :order_reference, :text, null: false
      add :state, :text, null: false, default: "contact_details"
      add :payment_status, :text, default: "pending"

      # Cart-flow fields (mirror the old orders shape, minus the snapshotted
      # totals which only make sense on a placed Order).
      add :customer_name, :text
      add :customer_email, :text
      add :gift, :boolean, default: false
      add :card_message, :text
      add :recipient_name, :text
      add :recipient_phone_number, :text
      add :delivery_address, :text
      add :delivery_instructions, :text
      add :fulfillment_date, :date
      add :fulfillment_amount, :decimal
      add :fulfillment_method, :text
      add :geocoded_address, :text
      add :here_id, :text
      add :distance, :bigint
      add :position, :text
      add :payment_intent_id, :text
      add :locale, :text, default: "sv-FI"

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :user_id,
          references(:users,
            column: :id,
            name: "carts_user_id_fkey",
            type: :uuid,
            prefix: "public"
          )

      add :fulfillment_option_id,
          references(:fulfillment_options,
            column: :id,
            name: "carts_fulfillment_option_id_fkey",
            type: :uuid,
            prefix: "public"
          )

      add :promotion_id,
          references(:promotions,
            column: :id,
            name: "carts_promotion_id_fkey",
            type: :uuid,
            prefix: "public"
          )

      # Set when :convert succeeds. Lets the audit/refund flow walk
      # cart -> order without an extra lookup by order_reference.
      add :order_id,
          references(:orders,
            column: :id,
            name: "carts_order_id_fkey",
            type: :uuid,
            prefix: "public"
          )
    end

    create unique_index(:carts, [:order_reference], name: "carts_unique_order_reference_index")

    # New table: cart_line_items
    create table(:cart_line_items, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :quantity, :bigint, default: 1
      add :unit_price, :decimal, null: false
      add :tax_rate, :decimal, null: false
      add :product_name, :text, null: false
      add :product_image_slug, :text, null: false
      add :is_card, :boolean, null: false, default: false
      add :card_size, :text

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :cart_id,
          references(:carts,
            column: :id,
            name: "cart_line_items_cart_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false

      add :product_id,
          references(:products,
            column: :id,
            name: "cart_line_items_product_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false

      add :product_variant_id,
          references(:product_variants,
            column: :id,
            name: "cart_line_items_product_variant_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end

    create unique_index(:cart_line_items, [:cart_id, :product_variant_id],
             name: "cart_line_items_unique_product_variant_index"
           )

    # New table: order_line_items (immutable snapshots).
    create table(:order_line_items, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :quantity, :bigint, default: 1
      add :unit_price, :decimal, null: false
      add :tax_rate, :decimal, null: false
      add :product_name, :text, null: false
      add :product_image_slug, :text, null: false
      add :is_card, :boolean, null: false, default: false
      add :card_size, :text

      # Snapshot values frozen at place-time.
      add :line_total, :decimal, null: false
      add :discount_amount, :decimal, null: false, default: 0
      add :line_tax_amount, :decimal, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :order_id,
          references(:orders,
            column: :id,
            name: "order_line_items_order_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false

      add :product_id,
          references(:products,
            column: :id,
            name: "order_line_items_product_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false

      add :product_variant_id,
          references(:product_variants,
            column: :id,
            name: "order_line_items_product_variant_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end

    # Reshape the existing `orders` table for the new immutable Order
    # resource. The `state` column is no longer needed (form-progress states
    # moved to Cart, and the conversion event creates the Order rather than
    # transitioning into :placed). Snapshotted totals are added.
    alter table(:orders) do
      remove :state

      add :line_total, :decimal
      add :line_tax_amount, :decimal
      add :discount_amount, :decimal, default: 0
      add :fulfillment_tax_amount, :decimal, default: 0
      add :tax_amount, :decimal
      add :total, :decimal
    end

    # Drop the legacy line_items table — replaced by cart_line_items /
    # order_line_items. PR 2 will handle moving any production data first.
    drop_if_exists unique_index(:line_items, [:order_id, :product_variant_id],
                     name: "line_items_unique_product_variant_index"
                   )

    drop_if_exists table(:line_items)
  end

  def down do
    # Re-create the legacy line_items table.
    create table(:line_items, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :quantity, :bigint, default: 1
      add :unit_price, :decimal, null: false
      add :tax_rate, :decimal, null: false
      add :product_name, :text, null: false
      add :product_image_slug, :text, null: false
      add :is_card, :boolean, null: false, default: false
      add :card_size, :text

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :order_id,
          references(:orders,
            column: :id,
            name: "line_items_order_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false

      add :product_id,
          references(:products,
            column: :id,
            name: "line_items_product_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false

      add :product_variant_id,
          references(:product_variants,
            column: :id,
            name: "line_items_product_variant_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end

    create unique_index(:line_items, [:order_id, :product_variant_id],
             name: "line_items_unique_product_variant_index"
           )

    alter table(:orders) do
      remove :total
      remove :tax_amount
      remove :fulfillment_tax_amount
      remove :discount_amount
      remove :line_tax_amount
      remove :line_total

      add :state, :text, null: false, default: "contact_details"
    end

    drop_if_exists unique_index(:cart_line_items, [:cart_id, :product_variant_id],
                     name: "cart_line_items_unique_product_variant_index"
                   )

    drop table(:cart_line_items)
    drop table(:order_line_items)

    drop_if_exists unique_index(:carts, [:order_reference],
                     name: "carts_unique_order_reference_index"
                   )

    drop table(:carts)
  end
end
