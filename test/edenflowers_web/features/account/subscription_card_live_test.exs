defmodule EdenflowersWeb.Account.SubscriptionCardLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Mox
  import Phoenix.LiveViewTest

  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.External.StripeAPI

  setup :verify_on_exit!

  setup %{conn: conn} do
    user = generate(admin_user(admin: false, name: "Ada Lovelace")) |> with_token()
    conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(user)

    %{conn: conn, user: user, subscription: generate(subscription(user_id: user.id))}
  end

  test "shows the card form for a SetupIntent on the subscription's customer", %{conn: conn, subscription: subscription} do
    subscription_id = subscription.id

    expect(StripeAPI.Mock, :create_setup_intent, fn "cus_ada", %{"subscription_id" => ^subscription_id} ->
      {:ok, %{id: "seti_1", client_secret: "seti_1_secret"}}
    end)

    {:ok, view, _html} = live(conn, ~p"/account/subscriptions/#{subscription.id}/card")

    assert has_element?(view, ~s|#card-form[data-intent="setup"][data-client-secret="seti_1_secret"]|)
  end

  # A new card restarts a held subscription but leaves the delivery owed.
  for state <- [:payment_failed, :active] do
    test "says a new card doesn't pay the delivery still owed, when #{state}", %{conn: conn, user: user} do
      subscription = generate(subscription(user_id: user.id, state: unquote(state)))

      stub(StripeAPI.Mock, :create_setup_intent, fn _customer, _metadata ->
        {:ok, %{id: "seti_1", client_secret: "s"}}
      end)

      generate(
        order(
          state: :placed,
          user_id: user.id,
          subscription_id: subscription.id,
          customer_name: "Ada Lovelace",
          customer_email: "ada@example.com",
          fulfillment_date: Date.add(Date.utc_today(), 2),
          quoted_fulfillment_fee: "5.00",
          ordered_at: DateTime.utc_now(),
          locale: "en",
          payment_link_token: "tok_held"
        )
      )

      {:ok, view, _html} = live(conn, ~p"/account/subscriptions/#{subscription.id}/card")

      assert has_element?(view, ~s|[data-testid=unpaid-occurrence] a[href="/pay/tok_held"]|, "Pay now")
    end
  end

  test "stores the card when Stripe returns, and goes back to the account", %{
    conn: conn,
    subscription: subscription
  } do
    expect(StripeAPI.Mock, :retrieve_setup_intent, fn "seti_1" ->
      {:ok,
       %{id: "seti_1", status: "succeeded", payment_method: "pm_new", metadata: %{"subscription_id" => subscription.id}}}
    end)

    {:ok, _view, html} =
      conn
      |> live(~p"/account/subscriptions/#{subscription.id}/card?setup_intent=seti_1&redirect_status=succeeded")
      |> follow_redirect(conn, ~p"/account")

    assert html =~ "Your card has been updated."
    assert Ash.reload!(subscription, authorize?: false).stripe_payment_method_id == "pm_new"
  end

  @tag capture_log: true
  test "asks Stripe once when the card couldn't be saved", %{conn: conn, subscription: subscription} do
    expect(StripeAPI.Mock, :retrieve_setup_intent, fn "seti_1" ->
      {:ok, %{id: "seti_1", status: "requires_payment_method", metadata: %{"subscription_id" => subscription.id}}}
    end)

    expect(StripeAPI.Mock, :create_setup_intent, fn "cus_ada", _metadata ->
      {:ok, %{id: "seti_2", client_secret: "seti_2_secret"}}
    end)

    {:ok, view, _html} =
      live(conn, ~p"/account/subscriptions/#{subscription.id}/card?setup_intent=seti_1&redirect_status=succeeded")

    assert render(view) =~ "Your card couldn&#39;t be saved."
    assert has_element?(view, ~s|#card-form[data-client-secret="seti_2_secret"]|)
  end

  test "won't open someone else's subscription", %{conn: conn} do
    theirs = generate(subscription(user_id: generate(admin_user(admin: false)).id))

    assert {:error, {:live_redirect, %{to: "/account"}}} =
             live(conn, ~p"/account/subscriptions/#{theirs.id}/card")
  end
end
