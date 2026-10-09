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
    generate(subscription(user_id: customer.id, product_variant_id: variant.id, interval_weeks: 2))

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions")

    assert has_element?(view, "[data-item-id]", "Ada Lovelace")
    assert has_element?(view, "[data-item-id]", "Large")
    assert has_element?(view, "[data-item-id]", "Every 2 weeks")
    assert has_element?(view, "[data-item-id]", "Active")
  end

  test "names the size in Jennie's language", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{Localize.Plug.PutLocale.session_key() => "sv-FI"})
      |> Helpers.store_in_session(admin)

    {:ok, customer} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)

    variant = generate(product_variant(product_id: generate(product()).id, size: :large))
    generate(subscription(user_id: customer.id, product_variant_id: variant.id))

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions")

    assert has_element?(view, "[data-item-id]", "Stor")
  end

  test "flags a subscription whose card was refused", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)

    {:ok, customer} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)

    generate(subscription(user_id: customer.id, state: :payment_failed))

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions")

    assert has_element?(view, "[data-item-id]", "Payment failed")
  end

  test "a row opens the subscription's page", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)

    {:ok, customer} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)

    subscription = generate(subscription(user_id: customer.id))

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions")

    refute has_element?(view, "[data-item-id] button")

    view |> element("[data-item-id] a", "Ada Lovelace") |> render_click()
    assert_redirect(view, ~p"/admin/subscriptions/#{subscription.id}")
  end

  test "searches subscriptions by customer name or email", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)

    {:ok, ada} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)
    {:ok, grace} = Edenflowers.Accounts.upsert_user("admiral@example.com", "Grace Hopper", authorize?: false)
    generate(subscription(user_id: ada.id))
    generate(subscription(user_id: grace.id))

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions?search=lovelace")
    assert has_element?(view, "[data-item-id]", "Ada Lovelace")
    refute has_element?(view, "[data-item-id]", "Grace Hopper")

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions?search=admiral")
    assert has_element?(view, "[data-item-id]", "Grace Hopper")
    refute has_element?(view, "[data-item-id]", "Ada Lovelace")
  end

  test "filters subscriptions by state", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)

    {:ok, ada} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)
    {:ok, grace} = Edenflowers.Accounts.upsert_user("grace@example.com", "Grace Hopper", authorize?: false)
    generate(subscription(user_id: ada.id))
    generate(subscription(user_id: grace.id, state: :paused))

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions?state=paused")

    assert has_element?(view, "[data-item-id]", "Grace Hopper")
    refute has_element?(view, "[data-item-id]", "Ada Lovelace")
  end
end
