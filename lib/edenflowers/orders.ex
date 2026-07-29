defmodule Edenflowers.Orders do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Orders.Order do
      define :create_for_checkout, action: :create_for_checkout
      define :get_order_by_id, action: :by_id, args: [:id]
      define :get_order_by_reference, action: :by_order_reference, args: [:order_reference]
      define :get_order_for_checkout, action: :for_checkout, args: [:id]
      define :list_completed_orders, action: :completed
      define :submit_contact_details, action: :submit_contact_details
      define :submit_gift_options, action: :submit_gift_options
      define :submit_delivery, action: :submit_delivery
      define :return_to_contact_details, action: :return_to_contact_details
      define :return_to_gift_options, action: :return_to_gift_options
      define :return_to_delivery, action: :return_to_delivery
      define :finalize_checkout, action: :finalize_checkout
      define :mark_payment_failed, action: :mark_payment_failed
      define :add_payment_intent_id, action: :add_payment_intent_id, args: [:payment_intent_id]
      define :mark_receipt_emailed, action: :mark_receipt_emailed, args: [:receipt_sha256]
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
      define :add_line_item, action: :add_line_item, args: [:product_variant_id, :quantity]
      define :increment_line_item, action: :increment_line_item, args: [:line_item_id]
      define :decrement_line_item, action: :decrement_line_item, args: [:line_item_id]
    end

    resource Edenflowers.Orders.LineItem
  end
end
