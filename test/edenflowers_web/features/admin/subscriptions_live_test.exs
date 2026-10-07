defmodule EdenflowersWeb.Admin.SubscriptionsLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Plug.Helpers

  test "lists subscriptions with their customer, size, interval and next date", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)

    {:ok, customer} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)
    variant = generate(product_variant(product_id: generate(product()).id, size: :large))

    Ash.Seed.seed!(Edenflowers.Orders.Subscription, %{
      user_id: customer.id,
      product_variant_id: variant.id,
      fulfillment_option_id: generate(fulfillment_option(fulfillment_method: :delivery)).id,
      interval_weeks: 2,
      next_fulfillment_date: ~D[2026-11-03],
      locale: "en",
      stripe_customer_id: "cus_ada",
      stripe_payment_method_id: "pm_card"
    })

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions")

    assert has_element?(view, "[data-item-id]", "Ada Lovelace")
    assert has_element?(view, "[data-item-id]", "Large")
    assert has_element?(view, "[data-item-id]", "Every 2 weeks")
    assert has_element?(view, "[data-item-id]", "Active")
  end

  test "flags a subscription whose card was refused", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)

    {:ok, customer} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)

    Ash.Seed.seed!(Edenflowers.Orders.Subscription, %{
      state: :payment_failed,
      user_id: customer.id,
      product_variant_id: generate(product_variant(product_id: generate(product()).id)).id,
      fulfillment_option_id: generate(fulfillment_option(fulfillment_method: :delivery)).id,
      interval_weeks: 1,
      next_fulfillment_date: ~D[2026-11-03],
      locale: "en",
      stripe_customer_id: "cus_ada",
      stripe_payment_method_id: "pm_card"
    })

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions")

    assert has_element?(view, "[data-item-id] .badge-error", "Payment failed")
  end
end
