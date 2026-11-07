defmodule EdenflowersWeb.Account.SubscriptionPlanPreviewLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias Edenflowers.Format
  alias Edenflowers.Fulfillment.Weekday
  alias Edenflowers.ShopTime

  setup %{conn: conn} do
    user = generate(admin_user(admin: false)) |> with_token()
    %{conn: log_in(conn, user), user: user}
  end

  test "previews edits without saving and keeps the selected fields until submission", %{conn: conn, user: user} do
    next = Date.add(ShopTime.today(), 27)
    subscription = generate(subscription(user_id: user.id, interval_weeks: 4, next_fulfillment_date: next))
    {:ok, view, _html} = live(conn, ~p"/account")
    form_id = "#change-subscription-#{subscription.id}"
    preview = "#{form_id} [data-testid=subscription-plan-preview]"
    refute has_element?(view, preview)

    params = %{"interval_weeks" => "1", "delivery_day" => to_string(Weekday.from_date(Date.add(next, 1)))}
    view |> form(form_id, params) |> render_change()
    expected = Date.add(ShopTime.today(), 7)
    assert has_element?(view, preview, Format.weekday_date(expected, "en-GB"))
    assert has_element?(view, ~s|#{form_id} select[name=interval_weeks] option[value="1"][selected]|)
    assert Ash.reload!(subscription, authorize?: false).next_fulfillment_date == next

    view |> form(form_id, params) |> render_submit()
    assert Ash.reload!(subscription, authorize?: false).next_fulfillment_date == expected
    refute has_element?(view, preview)

    notice = "#manage-subscription-#{subscription.id} [data-testid=subscription-notice]"

    assert has_element?(
             view,
             notice,
             "Changes saved. Your updated plan starts with the delivery on #{Format.weekday_date(expected, "en-GB")}."
           )

    assert has_element?(view, "#{form_id} button[disabled]")

    view |> form(form_id, %{"interval_weeks" => "2"}) |> render_change()
    assert has_element?(view, preview)
    refute has_element?(view, notice)
  end

  test "returning to the original plan hides its preview and disables saving", %{conn: conn, user: user} do
    subscription = generate(subscription(user_id: user.id))
    variant = Ash.get!(Edenflowers.Catalog.ProductVariant, subscription.product_variant_id)
    large = generate(product_variant(product_id: variant.product_id, size: :large, draft: false))
    {:ok, view, _html} = live(conn, ~p"/account")
    form_id = "#change-subscription-#{subscription.id}"
    preview = "#{form_id} [data-testid=subscription-plan-preview]"

    view |> form(form_id, %{"product_variant_id" => large.id}) |> render_change()
    assert has_element?(view, preview, Format.weekday_date(subscription.next_fulfillment_date, "en-GB"))
    refute has_element?(view, "#{form_id} button[disabled]")
    view |> form(form_id, %{"interval_weeks" => "4"}) |> render_change()

    original = %{"product_variant_id" => subscription.product_variant_id, "interval_weeks" => "2"}
    view |> form(form_id, original) |> render_change()
    refute has_element?(view, preview)
    assert has_element?(view, "#{form_id} button[disabled]")
  end

  test "a paused preview explains that resuming is conditional", %{conn: conn, user: user} do
    subscription =
      generate(subscription(user_id: user.id, state: :paused, next_fulfillment_date: Date.add(ShopTime.today(), -30)))

    {:ok, view, _html} = live(conn, ~p"/account")
    form_id = "#change-subscription-#{subscription.id}"
    preview = "#{form_id} [data-testid=subscription-plan-preview]"
    refute has_element?(view, preview)
    view |> form(form_id, %{"interval_weeks" => "4"}) |> render_change()

    {:ok, date} = Edenflowers.Orders.Subscription.preview_plan_change(subscription, %{interval_weeks: 4}, actor: user)
    assert has_element?(view, preview, "If you resume now")
    assert has_element?(view, preview, Format.weekday_date(date, "en-GB"))
    assert Ash.reload!(subscription, authorize?: false).state == :paused
  end

  test "a booked delivery keeps its original date while the preview describes the updated plan", %{
    conn: conn,
    user: user
  } do
    subscription = generate(subscription(user_id: user.id))

    booked =
      placed_order(
        user_id: user.id,
        subscription_id: subscription.id,
        fulfillment_date: ShopTime.today(),
        paid: true
      )

    {:ok, view, _html} = live(conn, ~p"/account")
    form_id = "#change-subscription-#{subscription.id}"
    view |> form(form_id, %{"interval_weeks" => "4"}) |> render_change()
    expected = Date.add(subscription.next_fulfillment_date, 14)

    assert has_element?(
             view,
             "#{form_id} [data-testid=subscription-plan-preview]",
             "Your updated plan starts with the delivery on #{Format.weekday_date(expected, "en-GB")}."
           )

    view |> form(form_id, %{"interval_weeks" => "4"}) |> render_submit()
    assert Ash.reload!(subscription, authorize?: false).next_fulfillment_date == expected
    assert Ash.reload!(booked, authorize?: false).fulfillment_date == ShopTime.today()
  end
end
