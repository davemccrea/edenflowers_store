defmodule EdenflowersWeb.AccountLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Store.Order

  setup %{conn: conn} do
    tax_rate = generate(tax_rate())
    delivery = generate(fulfillment_option(tax_rate_id: tax_rate.id, fulfillment_method: :delivery))
    pickup = generate(fulfillment_option(tax_rate_id: tax_rate.id, fulfillment_method: :pickup))

    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id))

    user = generate(admin_user(admin: false, name: "Sarah Smith")) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(user)

    %{
      conn: conn,
      user: user,
      delivery: delivery,
      pickup: pickup,
      product: product,
      variant: variant
    }
  end

  describe "empty state" do
    test "shows the empty-state copy and a Store link when no orders exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/account")

      assert html =~ "You haven&#39;t placed any orders yet."
      assert html =~ ~p"/store"
    end

    test "renders greeting with first name when set", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/account")
      assert html =~ "Hej Sarah"
    end

    test "falls back to 'Your account' when User has no name", %{conn: _conn} do
      anon = generate(admin_user(admin: false, name: nil)) |> with_token()

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Test.init_test_session(%{})
        |> Helpers.store_in_session(anon)

      {:ok, _view, html} = live(conn, ~p"/account")
      assert html =~ "Your account"
      refute html =~ "Hej "
    end

    test "shows the customer's email above the greeting", %{conn: conn, user: user} do
      {:ok, _view, html} = live(conn, ~p"/account")
      assert html =~ to_string(user.email)
    end

    test "renders a Sign out link to /sign-out", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/account")
      assert html =~ ~s|href="/sign-out"|
      assert html =~ "Sign out"
    end
  end

  describe "open orders section" do
    setup ctx do
      order = open_order_for(ctx.user, ctx.delivery, ctx.variant, %{recipient_name: "Anna"})
      [order: order]
    end

    test "renders the Open orders section with a count", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/account")
      assert html =~ "Open orders"
      assert html =~ "· 1"
    end

    test "renders the display title (single line item -> product name)", %{conn: conn, product: product} do
      {:ok, _view, html} = live(conn, ~p"/account")
      assert html =~ product.name
    end

    test "renders the fulfillment date prose with delivery verb", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/account")
      assert html =~ "Arriving" or html =~ "Ready for pickup"
    end

    test "renders the recipient meta line", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/account")
      assert html =~ "Anna"
    end

    test "renders the Message Jennie mailto link with order reference", %{conn: conn, order: order} do
      {:ok, _view, html} = live(conn, ~p"/account")
      expected_href = "mailto:info@edenflowers.fi?subject=Order+#{order.order_reference}"
      assert html =~ expected_href
      assert html =~ "Message Jennie"
    end

    test "renders a thumbnail image for the open order", %{conn: conn, variant: variant} do
      {:ok, _view, html} = live(conn, ~p"/account")
      assert html =~ variant.image_slug or html =~ "product"
    end

    test "Past orders section is hidden when only open orders exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/account")
      refute html =~ "Past orders"
    end
  end

  describe "past orders section" do
    setup ctx do
      order = past_order_for(ctx.user, ctx.delivery, ctx.variant, %{gift: false})
      [order: order]
    end

    test "renders the Past orders section with a count", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/account")
      assert html =~ "Past orders"
      assert html =~ "· 1"
    end

    test "non-gift order reads 'for yourself'", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/account")
      assert html =~ "for yourself"
    end

    test "gift order reads 'to {recipient}'", %{user: user, delivery: delivery, variant: variant} do
      past_order_for(user, delivery, variant, %{gift: true, recipient_name: "Mum"})

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Test.init_test_session(%{})
        |> Helpers.store_in_session(user)

      {:ok, _view, html} = live(conn, ~p"/account")
      assert html =~ "to Mum"
    end

    test "Open orders section is hidden when only past orders exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/account")
      refute html =~ "Open orders"
    end
  end

  describe "policy" do
    test "Order.get_open_orders/0 only returns the actor's orders", ctx do
      open_order_for(ctx.user, ctx.delivery, ctx.variant, %{})

      other_user = generate(admin_user(admin: false))
      open_order_for(other_user, ctx.delivery, ctx.variant, %{})

      assert [order] = Order.get_open_orders!(actor: ctx.user)
      assert order.user_id == ctx.user.id
    end

    test "Order.get_past_orders/0 only returns the actor's orders", ctx do
      past_order_for(ctx.user, ctx.delivery, ctx.variant, %{})

      other_user = generate(admin_user(admin: false))
      past_order_for(other_user, ctx.delivery, ctx.variant, %{})

      assert [order] = Order.get_past_orders!(actor: ctx.user)
      assert order.user_id == ctx.user.id
    end

    test ":open_orders excludes fulfilled orders", ctx do
      open_order_for(ctx.user, ctx.delivery, ctx.variant, %{})
      past_order_for(ctx.user, ctx.delivery, ctx.variant, %{})

      assert [open] = Order.get_open_orders!(actor: ctx.user)
      assert open.fulfillment_status == :pending
    end

    test ":past_orders excludes pending orders", ctx do
      open_order_for(ctx.user, ctx.delivery, ctx.variant, %{})
      past_order_for(ctx.user, ctx.delivery, ctx.variant, %{})

      assert [past] = Order.get_past_orders!(actor: ctx.user)
      assert past.fulfillment_status == :fulfilled
    end
  end

  describe "format_fulfillment_prose/2" do
    alias EdenflowersWeb.AccountLive

    test "delivery + today -> Arriving today" do
      today = ~D[2026-05-19]
      order = %{fulfillment_date: today, fulfillment_method: :delivery}
      assert AccountLive.format_fulfillment_prose(order, today) =~ "Arriving today"
    end

    test "delivery + tomorrow -> Arriving tomorrow" do
      today = ~D[2026-05-19]
      order = %{fulfillment_date: ~D[2026-05-20], fulfillment_method: :delivery}
      assert AccountLive.format_fulfillment_prose(order, today) =~ "Arriving tomorrow"
    end

    test "delivery + later -> Arriving on {date}" do
      today = ~D[2026-05-19]
      order = %{fulfillment_date: ~D[2026-05-26], fulfillment_method: :delivery}
      assert AccountLive.format_fulfillment_prose(order, today) =~ "Arriving on"
    end

    test "pickup + today -> Ready for pickup today" do
      today = ~D[2026-05-19]
      order = %{fulfillment_date: today, fulfillment_method: :pickup}
      assert AccountLive.format_fulfillment_prose(order, today) =~ "Ready for pickup today"
    end

    test "pickup + tomorrow -> Ready for pickup tomorrow" do
      today = ~D[2026-05-19]
      order = %{fulfillment_date: ~D[2026-05-20], fulfillment_method: :pickup}
      assert AccountLive.format_fulfillment_prose(order, today) =~ "Ready for pickup tomorrow"
    end

    test "missing date -> empty string" do
      today = ~D[2026-05-19]
      assert AccountLive.format_fulfillment_prose(%{fulfillment_date: nil}, today) == ""
    end
  end

  describe "mailto_for_order/1" do
    alias EdenflowersWeb.AccountLive

    test "URL-encodes the order reference into the subject" do
      order = %{order_reference: "EF-1847"}
      assert AccountLive.mailto_for_order(order) == "mailto:info@edenflowers.fi?subject=Order+EF-1847"
    end
  end

  describe "Order.display_title" do
    test "single non-card item -> product_name", ctx do
      order = open_order_for(ctx.user, ctx.delivery, ctx.variant, %{})
      [reloaded] = Order.get_open_orders!(actor: ctx.user)
      assert reloaded.display_title == ctx.product.name
      _ = order
    end

    test "card-only -> 'Order {ref}' fallback", ctx do
      order = build_placed_order(ctx.user, ctx.delivery, %{fulfillment_status: :pending})

      card_variant = generate(product_variant(product_id: ctx.product.id, size: :small))

      Ash.Seed.seed!(Edenflowers.Store.LineItem, %{
        order_id: order.id,
        product_id: ctx.product.id,
        product_variant_id: card_variant.id,
        quantity: 1,
        unit_price: Decimal.new("5.00"),
        tax_rate: Decimal.new("0.255"),
        product_name: "Card",
        product_image_slug: "card.png",
        is_card: true
      })

      [reloaded] = Order.get_open_orders!(actor: ctx.user)
      assert reloaded.display_title =~ "Order"
    end
  end

  defp open_order_for(user, fulfillment_option, variant, overrides) do
    attrs =
      %{
        user_id: user.id,
        fulfillment_status: :pending,
        fulfillment_option_id: fulfillment_option.id,
        fulfillment_method: fulfillment_option.fulfillment_method,
        fulfillment_date: Date.add(Date.utc_today(), 3),
        delivery_address: "Test Street 1, 65100 Vaasa"
      }
      |> Map.merge(overrides)

    order = build_placed_order(user, fulfillment_option, attrs)
    add_line_item(order, variant, false)
    order
  end

  defp past_order_for(user, fulfillment_option, variant, overrides) do
    attrs =
      %{
        user_id: user.id,
        fulfillment_status: :fulfilled,
        fulfillment_option_id: fulfillment_option.id,
        fulfillment_method: fulfillment_option.fulfillment_method,
        fulfillment_date: Date.add(Date.utc_today(), -7),
        ordered_at: DateTime.utc_now() |> DateTime.add(-7, :day),
        delivery_address: "Test Street 1, 65100 Vaasa"
      }
      |> Map.merge(overrides)

    order = build_placed_order(user, fulfillment_option, attrs)
    add_line_item(order, variant, false)
    order
  end

  defp build_placed_order(user, fulfillment_option, overrides) do
    base = %{
      state: :placed,
      order_reference: "EF-" <> (:crypto.strong_rand_bytes(3) |> Base.encode16()),
      user_id: user.id,
      customer_name: user.name,
      customer_email: to_string(user.email),
      fulfillment_option_id: fulfillment_option.id,
      fulfillment_method: fulfillment_option.fulfillment_method,
      fulfillment_fee: Decimal.new("4.50"),
      fulfillment_tax_percentage: Decimal.new("0.255"),
      ordered_at: DateTime.utc_now(),
      gift: false
    }

    generate(order(Map.merge(base, overrides)))
  end

  defp add_line_item(order, variant, is_card?) do
    Ash.Seed.seed!(Edenflowers.Store.LineItem, %{
      order_id: order.id,
      product_id: variant.product_id,
      product_variant_id: variant.id,
      quantity: 1,
      unit_price: variant.price,
      tax_rate: Decimal.new("0.255"),
      product_name: order_product_name(variant),
      product_image_slug: variant.image_slug,
      is_card: is_card?
    })
  end

  defp order_product_name(variant) do
    product = Ash.get!(Edenflowers.Store.Product, variant.product_id, authorize?: false)
    product.name
  end

  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end
