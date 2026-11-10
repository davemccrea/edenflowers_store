defmodule Edenflowers.EventsTest do
  use ExUnit.Case, async: true

  alias Ash.Notifier.PubSub.Info
  alias Edenflowers.Accounts.User
  alias Edenflowers.Bank.Connection
  alias Edenflowers.Catalog.Product
  alias Edenflowers.Catalog.ProductVariant
  alias Edenflowers.Courses.Course
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Events
  alias Edenflowers.Expenses.Expense
  alias Edenflowers.Fulfillment.FulfillmentOption
  alias Edenflowers.Fulfillment.ShopCalendar
  alias Edenflowers.Orders.LineItem
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Subscription
  alias Edenflowers.Payments.CreditNote
  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Pricing.Promotion
  alias Edenflowers.Pricing.WelcomeOffer

  @resources [
    {Order,
     [
       Events.admin_orders(),
       Events.admin_order(:id),
       Events.order_changed(:id),
       Events.order_placed(:id),
       Events.order_paid(:id),
       Events.order_checkout_restarted(:id),
       Events.line_items_changed(:id)
     ]},
    {Subscription,
     [
       Events.admin_subscriptions(),
       Events.admin_subscription(:id)
     ]},
    {CourseRegistration, [Events.admin_bookings(), Events.course_registration_paid(:id)]},
    {Course, [Events.admin_courses(), Events.admin_course(:id)]},
    {Product, [Events.admin_products(), Events.admin_product(:id)]},
    {ProductVariant,
     [Events.admin_products(), Events.admin_product(:product_id), Events.product_variant_changed(:product_id)]},
    {User, [Events.admin_customers(), Events.admin_customer(:id)]},
    {Promotion, [Events.admin_promotions(), Events.admin_promotion(:id), Events.admin_pass_it_on()]},
    {WelcomeOffer, [Events.admin_welcome_offer()]},
    {Invoice, [Events.admin_invoices(), Events.admin_invoice(:id), Events.admin_order(:order_id)]},
    {CreditNote, [Events.admin_invoices(), Events.admin_invoice(:invoice_id), Events.admin_order(:order_id)]},
    {Expense, [Events.admin_expenses(), Events.admin_expense(:id)]},
    {FulfillmentOption, [Events.admin_fulfillment_options(), Events.admin_fulfillment_option(:id)]},
    {ShopCalendar, [Events.shop_calendar_changed()]},
    {Connection, [Events.admin_bank()]},
    {LineItem, [Events.line_items_changed(:order_id)]}
  ]

  test "every admin-facing resource publishes the topics its pages follow" do
    for {resource, expected_topics} <- @resources do
      assert Info.module(resource) == EdenflowersWeb.Endpoint,
             "#{inspect(resource)} must publish through the app's endpoint"

      published =
        resource
        |> Info.publications()
        |> Enum.map(&Events.topic(&1.topic))

      for topic <- expected_topics do
        assert Events.topic(topic) in published,
               "#{inspect(resource)} does not publish #{inspect(Events.topic(topic))}"
      end
    end
  end
end
