defmodule EdenflowersWeb.Admin.SubscriptionsLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  test "lists subscriptions with their customer, size, interval and next date", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = log_in(conn, admin)

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

    conn = log_in(conn, admin, %{Localize.Plug.PutLocale.session_key() => "sv-FI"})

    {:ok, customer} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)

    variant = generate(product_variant(product_id: generate(product()).id, size: :large))
    generate(subscription(user_id: customer.id, product_variant_id: variant.id))

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions")

    assert has_element?(view, "[data-item-id]", "Stor")
  end

  test "flags a subscription whose card was refused", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = log_in(conn, admin)

    {:ok, customer} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)

    generate(subscription(user_id: customer.id, state: :payment_failed))

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions")

    assert has_element?(view, "[data-item-id]", "Payment failed")
  end

  test "a row opens the subscription's page", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = log_in(conn, admin)

    {:ok, customer} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)

    subscription = generate(subscription(user_id: customer.id))

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions")

    refute has_element?(view, "[data-item-id] button")

    view |> element("[data-item-id] a", "Ada Lovelace") |> render_click()
    assert_redirect(view, ~p"/admin/subscriptions/#{subscription.id}")
  end

  test "searches subscriptions by customer name or email", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = log_in(conn, admin)

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
    conn = log_in(conn, admin)

    {:ok, ada} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)
    {:ok, grace} = Edenflowers.Accounts.upsert_user("grace@example.com", "Grace Hopper", authorize?: false)
    generate(subscription(user_id: ada.id))
    generate(subscription(user_id: grace.id, state: :paused))

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions?state=paused")

    assert has_element?(view, "[data-item-id]", "Grace Hopper")
    refute has_element?(view, "[data-item-id]", "Ada Lovelace")
  end

  test "sorts sizes small to large, not alphabetically", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = log_in(conn, admin)

    for {name, size} <- [{"Lars Large", :large}, {"Sam Small", :small}, {"Mia Medium", :medium}] do
      {:ok, customer} = Edenflowers.Accounts.upsert_user("#{size}@example.com", name, authorize?: false)
      variant = generate(product_variant(product_id: generate(product()).id, size: size))
      generate(subscription(user_id: customer.id, product_variant_id: variant.id))
    end

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions")
    view |> element("[phx-click=toggle_sort][phx-value-key='product_variant.size_rank']") |> render_click()

    assert row_names(render(view), ["Lars Large", "Sam Small", "Mia Medium"]) == [
             "Sam Small",
             "Mia Medium",
             "Lars Large"
           ]
  end

  # Ranked from a list in the resource, so a new state must be added there too or it sorts last.
  test "sorts states in the state machine's order", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = log_in(conn, admin)
    states = AshStateMachine.Info.state_machine_all_states(Edenflowers.Orders.Subscription)

    for state <- Enum.reverse(states) do
      {:ok, customer} = Edenflowers.Accounts.upsert_user("#{state}@example.com", "Customer #{state}", authorize?: false)
      generate(subscription(user_id: customer.id, state: state))
    end

    {:ok, _view, html} = live(conn, ~p"/admin/subscriptions?sort=state_rank")
    names = Enum.map(states, &"Customer #{&1}")
    assert row_names(html, names) == names
  end

  # The filter offers whatever the state machine holds, so a new state must get a label.
  test "labels every subscription state" do
    for state <- AshStateMachine.Info.state_machine_all_states(Edenflowers.Orders.Subscription) do
      assert is_binary(EdenflowersWeb.Admin.Components.subscription_state_label(state))
    end
  end

  defp row_names(html, names) do
    rows = html |> String.split("<tbody") |> List.last()
    Enum.sort_by(names, &(rows |> :binary.match(&1) |> elem(0)))
  end
end
