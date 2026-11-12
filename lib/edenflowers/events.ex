defmodule Edenflowers.Events do
  @moduledoc """
  The PubSub topics that Ash resources publish and LiveViews follow.

  Resources publish from their `pub_sub` block; LiveViews subscribe in
  `mount/3` once connected. Both sides call these functions, so a topic name
  cannot drift between the publisher and its subscribers.

  A topic is a list of segments. Ash replaces atom segments with record fields
  when it publishes; `topic/1` joins concrete segments for a subscription.

  Admin topics follow one shape:

      admin:<collection>                    a list page
      admin:<collection>:<id>               one record's detail page

  Topics without the `admin` prefix are shared with the storefront, where the
  customer's own page follows the same change.
  """

  @pubsub Edenflowers.PubSub

  ## Admin collections

  def admin_orders, do: ["admin", "orders"]
  def admin_customers, do: ["admin", "customers"]
  def admin_subscriptions, do: ["admin", "subscriptions"]
  def admin_bookings, do: ["admin", "bookings"]
  def admin_courses, do: ["admin", "courses"]
  def admin_products, do: ["admin", "products"]
  def admin_product_categories, do: ["admin", "product_categories"]
  def admin_promotions, do: ["admin", "promotions"]
  def admin_welcome_offer, do: ["admin", "welcome_offer"]
  def admin_invoices, do: ["admin", "invoices"]
  def admin_expenses, do: ["admin", "expenses"]
  def admin_fulfillment_options, do: ["admin", "fulfillment_options"]
  def admin_pass_it_on, do: ["admin", "pass_it_on"]
  def admin_bank, do: ["admin", "bank"]

  ## Admin records

  def admin_order(id), do: ["admin", "orders", id]
  def admin_customer(id), do: ["admin", "customers", id]
  def admin_subscription(id), do: ["admin", "subscriptions", id]
  def admin_course(id), do: ["admin", "courses", id]
  def admin_product(id), do: ["admin", "products", id]
  def admin_promotion(id), do: ["admin", "promotions", id]
  def admin_fulfillment_option(id), do: ["admin", "fulfillment_options", id]
  def admin_invoice(id), do: ["admin", "invoices", id]
  def admin_expense(id), do: ["admin", "expenses", id]

  def admin_report(user_id), do: ["admin", "reports", user_id]

  ## Shared with the storefront

  def order_changed(id), do: ["order", "changed", id]
  def order_placed(id), do: ["order", "placed", id]
  def order_paid(id), do: ["order", "paid", id]
  def order_checkout_restarted(id), do: ["order", "checkout_restarted", id]
  def line_items_changed(order_id), do: ["line_item", "changed", order_id]
  def course_registration_paid(id), do: ["course_registration", "paid", id]
  def product_variant_changed(product_id), do: ["product_variant", "changed", product_id]
  def shop_calendar_changed, do: ["shop_calendar", "changed"]
  def store_presence, do: ["store", "presence"]

  @doc "Subscribes the calling process to `topic`, a list of concrete segments."
  def subscribe(topic), do: Phoenix.PubSub.subscribe(@pubsub, topic(topic))

  def unsubscribe(topic), do: Phoenix.PubSub.unsubscribe(@pubsub, topic(topic))

  def broadcast(topic, message), do: Phoenix.PubSub.broadcast(@pubsub, topic(topic), message)

  def topic(topic) when is_binary(topic), do: topic
  def topic(topic) when is_list(topic), do: Enum.join(topic, ":")
end
