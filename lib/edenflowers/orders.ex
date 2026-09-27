defmodule Edenflowers.Orders do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain, AshAi]

  admin do
    show?(true)
  end

  @order_list_fields [
    :id,
    :order_reference,
    :ordered_at,
    :payment_status,
    :fulfillment_status,
    :customer_name,
    :gift,
    :recipient_name,
    :card_message,
    :fulfillment_date,
    :fulfillment_method,
    :fulfillment_option_name,
    :delivery_address
  ]

  tools do
    tool :list_open_orders, Edenflowers.Orders.Order, :open do
      description "Placed orders not yet delivered or collected, soonest fulfilment date first. Includes unpaid orders, so check payment_status."
      select @order_list_fields
      load [:grand_total, :distance_km, line_items: [:product_name, :variant_size, :quantity, :is_card]]
      load_strict? true
    end

    tool :list_recent_orders, Edenflowers.Orders.Order, :admin_list do
      description "All placed orders, newest first, fulfilled or not. Use limit to page."
      select @order_list_fields
      load [:grand_total]
    end

    tool :get_order, Edenflowers.Orders.Order, :admin_show do
      description "Full details of one placed order by its id."

      select @order_list_fields ++
               [
                 :customer_email,
                 :recipient_phone_number,
                 :delivery_instructions,
                 :amount_paid,
                 :promotion_name,
                 :promotion_code,
                 :fulfillment_fee
               ]

      load [
        :grand_total,
        :items_total,
        :vat,
        :discount,
        :distance_km,
        :amount_mismatch?,
        line_items: [:product_name, :variant_size, :quantity, :unit_price, :is_card, :total]
      ]

      load_strict? true
    end

    tool :mark_order_fulfilled, Edenflowers.Orders.Order, :mark_fulfilled do
      description "Marks a pending order as delivered or collected."
      select [:id, :order_reference, :fulfillment_status]
    end

    tool :sales_summary, Edenflowers.Orders.Order, :sales_summary
  end

  resources do
    resource Edenflowers.Orders.Order do
      define :create_for_checkout, action: :create_for_checkout
      define :get_order_by_id, action: :read, get_by: [:id]
      define :get_order_for_checkout, action: :for_checkout, args: [:id]
      define :get_order_for_admin, action: :admin_show, args: [:id]
      define :list_my_orders, action: :mine
      define :list_open_orders, action: :open
      define :list_orders_to_fulfil, action: :to_fulfil
      define :sales_summary, action: :sales_summary, args: [:from, :to]
      define :submit_contact_details, action: :submit_contact_details
      define :submit_gift_options, action: :submit_gift_options
      define :submit_delivery, action: :submit_delivery
      define :return_to_contact_details, action: :return_to_contact_details
      define :return_to_gift_options, action: :return_to_gift_options
      define :return_to_delivery, action: :return_to_delivery
      define :finalize_checkout, action: :finalize_checkout, args: [:payment_intent_id]
      define :mark_payment_failed, action: :mark_payment_failed, args: [:payment_intent_id]
      define :mark_order_fulfilled, action: :mark_fulfilled
      define :add_payment_intent_id, action: :add_payment_intent_id, args: [:payment_intent_id]
      define :add_promotion_with_id, action: :add_promotion_with_id, args: [:promotion_id]
      define :add_promotion_with_code, action: :add_promotion_with_code, args: [:code]
      define :clear_promotion, action: :clear_promotion
      define :update_fulfillment_option, action: :update_fulfillment_option, args: [:fulfillment_option_id]
      define :set_gift, action: :set_gift, args: [:gift]
      define :update_locale, action: :update_locale, args: [:locale]
      define :restart_checkout, action: :restart_checkout
      define :add_card, action: :add_card, args: [:product_variant_id]
      define :remove_card, action: :remove_card
      define :remove_line_item, action: :remove_line_item, args: [:line_item_id]
    end

    resource Edenflowers.Orders.LineItem do
      define :add_line_item, action: :add_to_cart, args: [:order_id, :product_variant_id, :quantity]
      define :increment_line_item, action: :increment_quantity
      define :decrement_line_item, action: :decrement_quantity
    end
  end
end
