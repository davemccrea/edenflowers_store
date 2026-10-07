defmodule EdenflowersWeb.Account.SubscriptionCardLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Mox
  import Phoenix.LiveViewTest

  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders.Subscription

  setup :verify_on_exit!

  setup %{conn: conn} do
    user = generate(admin_user(admin: false, name: "Ada Lovelace")) |> with_token()
    conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(user)

    %{conn: conn, user: user, subscription: subscription(user, %{})}
  end

  defp subscription(user, attrs) do
    Ash.Seed.seed!(
      Subscription,
      Map.merge(
        %{
          user_id: user.id,
          product_variant_id: generate(product_variant(product_id: generate(product()).id)).id,
          fulfillment_option_id: generate(fulfillment_option(fulfillment_method: :delivery)).id,
          interval_weeks: 2,
          next_fulfillment_date: Date.add(Date.utc_today(), 14),
          locale: "en",
          stripe_customer_id: "cus_ada",
          stripe_payment_method_id: "pm_old"
        },
        attrs
      )
    )
  end

  test "shows the card form for a SetupIntent on the subscription's customer", %{conn: conn, subscription: subscription} do
    subscription_id = subscription.id

    expect(StripeAPI.Mock, :create_setup_intent, fn "cus_ada", %{"subscription_id" => ^subscription_id} ->
      {:ok, %{id: "seti_1", client_secret: "seti_1_secret"}}
    end)

    {:ok, view, _html} = live(conn, ~p"/account/subscriptions/#{subscription.id}/card")

    assert has_element?(view, ~s|#card-form[data-intent="setup"][data-client-secret="seti_1_secret"]|)
  end

  test "stores the card when Stripe returns, and goes back to the account", %{
    conn: conn,
    subscription: subscription
  } do
    expect(StripeAPI.Mock, :retrieve_setup_intent, fn "seti_1" ->
      {:ok,
       %{id: "seti_1", status: "succeeded", payment_method: "pm_new", metadata: %{"subscription_id" => subscription.id}}}
    end)

    assert {:error, {:live_redirect, %{to: "/account", flash: %{"info" => "Your card has been updated."}}}} =
             live(
               conn,
               ~p"/account/subscriptions/#{subscription.id}/card?setup_intent=seti_1&redirect_status=succeeded"
             )

    assert Ash.reload!(subscription, authorize?: false).stripe_payment_method_id == "pm_new"
  end

  test "won't open someone else's subscription", %{conn: conn} do
    theirs = subscription(generate(admin_user(admin: false)), %{})

    assert {:error, {:live_redirect, %{to: "/account"}}} =
             live(conn, ~p"/account/subscriptions/#{theirs.id}/card")
  end
end
