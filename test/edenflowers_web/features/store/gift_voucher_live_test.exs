defmodule EdenflowersWeb.Store.GiftVoucherLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders.Order

  setup :verify_on_exit!

  @details %{
    "amount" => "70",
    "recipient_name" => "Mia",
    "card_message" => "Grattis!",
    "voucher_locale" => "fi",
    "customer_name" => "Anna Buyer",
    "customer_email" => "anna@example.com"
  }

  defp sale(id), do: Ash.get!(Order, id, load: [:grand_total], authorize?: false)

  test "a guest buys a voucher in Swedish, changes the amount, then pays by card", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/sv/presentkort")

    view |> form("#gift-voucher-form", form: @details) |> render_submit()
    assert has_element?(view, "[data-testid=payment-section]", "till Mia")

    [%{id: id}] = Ash.read!(Order, authorize?: false)
    started = sale(id)
    assert started.state == :payment
    assert Decimal.eq?(started.grand_total, 70)
    assert started.voucher_locale == "fi"
    assert started.locale == "sv-FI"

    view |> element("button", "Ändra") |> render_click()
    view |> form("#gift-voucher-form", form: %{@details | "amount" => "40"}) |> render_submit()
    assert Decimal.eq?(sale(id).grand_total, 40)

    expect(StripeAPI.Mock, :create_payment_intent, fn 4000, %{"order_id" => ^id}, nil ->
      {:ok, %{id: "pi_voucher", client_secret: "pi_secret", amount: 4000}}
    end)

    view |> element("#gift-voucher-payment-form") |> render_submit()
    assert_push_event(view, "stripe:process_payment", %{client_secret: "pi_secret"})
  end

  test "previews the voucher as it's filled in, and offers Christmas only while Jennie does", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/en/gift-voucher")
    render_async(view)
    assert has_element?(view, "img[data-testid=voucher-preview]")
    refute has_element?(view, "input[name='form[voucher_style]'][value=christmas]")

    calendar = Edenflowers.Fulfillment.get_shop_calendar!(authorize?: false)
    Edenflowers.Fulfillment.set_christmas_vouchers_online!(calendar, true, authorize?: false)

    {:ok, view, _html} = live(conn, "/en/gift-voucher")
    view |> form("#gift-voucher-form", form: Map.put(@details, "voucher_style", "christmas")) |> render_submit()

    [%{id: id}] = Ash.read!(Order, authorize?: false)
    assert sale(id).voucher_style == :christmas
  end

  test "asks who the voucher is for before taking payment", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/en/gift-voucher")

    view |> form("#gift-voucher-form", form: %{@details | "recipient_name" => ""}) |> render_submit()

    refute has_element?(view, "[data-testid=payment-section]")
    assert has_element?(view, "#gift-voucher-form", "This field is required")
    assert Ash.read!(Order, authorize?: false) == []
  end
end
