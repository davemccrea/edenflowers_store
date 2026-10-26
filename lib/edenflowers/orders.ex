defmodule Edenflowers.Orders do
  @moduledoc """
  Entry point for carts, placed orders, and subscriptions.

  `Order` holds checkout and fulfillment state; `LineItem` holds what was
  bought; `Subscription` schedules future occurrence orders.
  """

  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Orders.Order do
      # Lookups
      define :get_order_by_id, action: :read, get_by: [:id]
      define :get_order_for_checkout, action: :for_checkout, get_by: [:id]
      define :get_order_for_admin, action: :admin_show, get_by: [:id]
      define :search_orders, action: :search, args: [:term]
      define :get_last_order_with_customer_phone, action: :last_with_customer_phone, args: [:customer_id]
      define :list_my_orders, action: :mine
      define :list_orders_due_soon, action: :due_soon
      define :list_orders_to_fulfil, action: :to_fulfil
      define :list_unsettled_orders, action: :unsettled
      define :sales_summary, action: :sales_summary, args: [:from, :to]

      # Checkout
      define :create_for_checkout, action: :create_for_checkout
      define :submit_contact_details, action: :submit_contact_details
      define :submit_gift_options, action: :submit_gift_options
      define :submit_delivery, action: :submit_delivery
      define :return_to_contact_details, action: :return_to_contact_details
      define :return_to_gift_options, action: :return_to_gift_options
      define :return_to_delivery, action: :return_to_delivery
      define :finalize_checkout, action: :finalize_checkout, args: [:payment_intent_id]
      define :prepare_checkout_payment, action: :prepare_checkout_payment, args: [:order_id]
      define :add_promotion_with_code, action: :add_promotion_with_code, args: [:code]
      define :clear_promotion, action: :clear_promotion
      define :update_fulfillment_option, action: :update_fulfillment_option, args: [:fulfillment_option_id]
      define :set_gift, action: :set_gift, args: [:gift]
      define :update_locale, action: :update_locale, args: [:locale]
      define :restart_checkout, action: :restart_checkout
      define :add_card, action: :add_card, args: [:product_variant_id]
      define :remove_card, action: :remove_card
      define :remove_line_item, action: :remove_line_item, args: [:line_item_id]

      # Occurrences
      define :create_occurrence, action: :create_occurrence
      define :get_occurrence, action: :read, get_by_identity: :unique_occurrence
      define :place_unpaid_occurrence, action: :place_unpaid_occurrence

      # Admin
      define :mark_order_fulfilled, action: :mark_fulfilled
      define :email_fulfillment_confirmation, action: :email_fulfillment_confirmation
      define :place_custom_order, action: :place_custom
      define :edit_order, action: :edit
      define :quote_entered_order, action: :quote_entered, args: [:order, :params, :delivery_quote]
      define :update_florist_note, action: :update_florist_note
      define :cancel_order, action: :cancel
      define :refresh_vat_breakdown, action: :refresh_vat_breakdown

      # Customer
      define :cancel_order_by_customer, action: :cancel_by_customer

      # Payments and links
      define :add_payment_intent_id, action: :add_payment_intent_id, args: [:payment_intent_id]
      define :mark_payment_cancelled, action: :mark_payment_cancelled, args: [:payment_intent_id]
      define :prepare_order_link_payment, action: :prepare_link_payment, args: [:token, :shown_balance]
      define :record_payment, action: :record_payment, args: [:amount, :payment_method]
      define :undo_payment, action: :undo_payment, args: [:payment_id]
      define :add_customer_email, action: :add_customer_email, args: [:customer_email]
      define :record_link_payment, action: :record_link_payment, args: [:payment_intent_id]
      define :open_payment_link, action: :open_payment_link
      define :get_order_by_payment_link_token, action: :by_payment_link_token, args: [:token]

      # Emails
      define :send_order_details_email, action: :send_order_details_email
      define :email_receipt, action: :email_receipt
      define :send_payment_reminder, action: :send_payment_reminder

      # The charged fee for a quote not yet on an order, by the order's own rule.
      define_calculation :charged_fulfillment_fee,
        calculation: :fee_for_cart,
        args: [:quoted_fulfillment_fee, :in_free_delivery_zone, :free_delivery?, {:optional, :fulfillment_fee_override}]
    end

    resource Edenflowers.Orders.Order.Version

    resource Edenflowers.Orders.Subscription do
      define :activate_subscription, action: :activate
      define :reactivate_subscription, action: :reactivate
      define :get_subscription, action: :read, get_by: [:id]
      define :list_my_subscriptions, action: :mine
      define :list_failed_subscriptions, action: :payment_failed
      define :pause_subscription, action: :pause
      define :resume_subscription, action: :resume
      define :cancel_subscription, action: :cancel
      define :change_subscription, action: :change
      define :replace_subscription_card, action: :replace_card, args: [:stripe_payment_method_id]
    end

    resource Edenflowers.Orders.Subscription.Version

    resource Edenflowers.Orders.LineItem do
      define :add_line_item, action: :add_to_cart, args: [:order_id, :product_variant_id, :quantity]
      define :increment_line_item, action: :increment_quantity
      define :decrement_line_item, action: :decrement_quantity
    end
  end
end
