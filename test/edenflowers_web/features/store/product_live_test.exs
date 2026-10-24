defmodule EdenflowersWeb.Store.ProductLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias Edenflowers.Orders
  alias Edenflowers.Orders.LineItem

  setup %{conn: conn} do
    order = generate(order())
    %{conn: Plug.Test.init_test_session(conn, %{order_id: order.id}), order: order}
  end

  test "a one-size product has no size to choose, and still adds to the cart", %{conn: conn, order: order} do
    product = generate(product(draft: false))
    generate(product_variant(product_id: product.id, size: nil, price: "6.00"))

    {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")

    refute has_element?(view, "legend", "Size")
    assert has_element?(view, "[data-testid=product-price]", "6")

    view |> form("[data-testid=product-form]") |> render_submit()

    assert [%LineItem{variant_size: nil}] = line_items(order)
  end

  test "a sold-out size can't be picked, and isn't picked to start with", %{conn: conn} do
    product = generate(product(draft: false))
    generate(product_variant(product_id: product.id, size: :small, price: "40.00"))
    generate(product_variant(product_id: product.id, size: :medium, price: "50.00", stock_quantity: 0))
    generate(product_variant(product_id: product.id, size: :large, price: "60.00"))

    {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")

    assert has_element?(view, "[data-testid=variant-option-medium][disabled]")
    assert has_element?(view, "label", "Sold out")
    refute has_element?(view, "[data-testid=variant-option-medium][checked]")
    assert has_element?(view, "[data-testid=add-to-cart-button]:not([disabled])", "Add to cart")
  end

  test "shows the chosen size's height and stems, leaving out what's not filled in", %{conn: conn} do
    product = generate(product(draft: false))
    small = generate(product_variant(product_id: product.id, size: :small, height_cm: "30–40", stem_count: "10–12"))
    large = generate(product_variant(product_id: product.id, size: :large, height_cm: "50–60", stem_count: nil))
    plain = generate(product_variant(product_id: product.id, size: :medium, height_cm: nil, stem_count: nil))

    {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")

    view |> form("[data-testid=product-form]", %{product_variant_id: small.id}) |> render_change()
    assert has_element?(view, "[data-testid=variant-dimensions]", "30–40 cm · 10–12 stems")

    view |> form("[data-testid=product-form]", %{product_variant_id: large.id}) |> render_change()
    assert render(element(view, "[data-testid=variant-dimensions]")) =~ ~r/>\s*50–60 cm\s*</

    view |> form("[data-testid=product-form]", %{product_variant_id: plain.id}) |> render_change()
    refute has_element?(view, "[data-testid=variant-dimensions]")
  end

  test "shows only the details its category's product type has", %{conn: conn} do
    category = generate(product_category(product_type: :plant))
    product = generate(product(draft: false, product_category_id: category.id))
    generate(product_variant(product_id: product.id, size: nil, height_cm: "40", stem_count: "12", pot_cm: "14"))

    {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")

    assert render(element(view, "[data-testid=variant-dimensions]")) =~ ~r/>\s*40 cm · Pot 14 cm\s*</
  end

  test "a product with every size sold out can't be added", %{conn: conn} do
    product = generate(product(draft: false))
    generate(product_variant(product_id: product.id, size: nil, stock_quantity: 0))

    {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")

    assert has_element?(view, "[data-testid=add-to-cart-button][disabled]", "Sold out")
  end

  test "a size bought out by someone else shows as sold out without a reload", %{conn: conn} do
    product = generate(product(draft: false, tax_rate_id: generate(tax_rate()).id))
    variant = generate(product_variant(product_id: product.id, size: nil, stock_quantity: 1))

    {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")
    refute has_element?(view, "[data-testid=add-to-cart-button][disabled]")

    other_order = generate(order(state: :payment, payment_intent_id: "pi_test"))
    generate(line_item(order_id: other_order.id, product_variant_id: variant.id, quantity: 1))
    other_order = Ash.load!(other_order, :grand_total, authorize?: false)

    Orders.finalize_checkout!(other_order.id, "pi_test", %{amount_paid: other_order.grand_total}, authorize?: false)

    assert has_element?(view, "[data-testid=add-to-cart-button][disabled]", "Sold out")
  end

  test "the cart says when there are no more to add", %{conn: conn, order: order} do
    product = generate(product(draft: false))
    variant = generate(product_variant(product_id: product.id, size: nil, stock_quantity: 1))
    line_item = Orders.add_line_item!(order.id, variant.id, 1, authorize?: false)

    {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")

    view |> element("#cart-line-items-increment-#{line_item.id}") |> render_click()

    assert has_element?(view, "#cart-line-items [role=alert]", "Only 1 left")
  end

  describe "a subscribable product" do
    setup do
      product = generate(product(subscribable: true, free_delivery: true, draft: false))
      %{product: product, variant: generate(product_variant(product_id: product.id))}
    end

    test "starts as a one-time purchase", %{conn: conn, product: product, order: order} do
      {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")

      refute has_element?(view, "[data-testid=subscribe-option][checked]")
      assert has_element?(view, "[data-testid=subscription-faq] summary", "When do I pay?")
      refute has_element?(view, "[data-testid=interval-options]")
      refute has_element?(view, "[data-testid=per-delivery]")

      view |> form("[data-testid=product-form]") |> render_submit()

      assert [%LineItem{interval_weeks: nil}] = line_items(order)
    end

    test "can be subscribed to every few weeks", %{conn: conn, product: product, variant: variant, order: order} do
      {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")
      view |> form("[data-testid=product-form]", %{subscribe: "true"}) |> render_change()

      assert has_element?(view, "[data-testid=interval-option-4]")
      assert has_element?(view, "[data-testid=per-delivery]", "per delivery")

      view
      |> form("[data-testid=product-form]", %{product_variant_id: variant.id, subscribe: "true", interval_weeks: "2"})
      |> render_change()

      assert render_submit(form(view, "[data-testid=product-form]"))
      assert_push_event(view, "js-exec", %{to: "#cart-drawer"})
      assert [%LineItem{interval_weeks: 2, quantity: 1}] = line_items(order)
    end

    test "starts from what's in the cart, and offers to update it", %{
      conn: conn,
      product: product,
      variant: variant,
      order: order
    } do
      Orders.add_line_item!(order.id, variant.id, 1, %{interval_weeks: 2}, authorize?: false)
      {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")

      assert has_element?(view, "[data-testid=interval-option-2][checked]")
      assert has_element?(view, "[data-testid=add-to-cart-button]", "Show cart")

      view
      |> form("[data-testid=product-form]", %{product_variant_id: variant.id, subscribe: "false"})
      |> render_change()

      refute has_element?(view, "[data-testid=replaces-cart-note]")
      assert has_element?(view, "[data-testid=add-to-cart-button]", "Update cart")

      view |> form("[data-testid=product-form]") |> render_submit()

      assert [%LineItem{interval_weeks: nil}] = line_items(order)
    end

    test "counts the bouquets subscribing replaces", %{conn: conn, product: product, variant: variant, order: order} do
      Orders.add_line_item!(order.id, variant.id, 3, authorize?: false)
      {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")

      view
      |> form("[data-testid=product-form]", %{product_variant_id: variant.id, subscribe: "true"})
      |> render_change()

      assert has_element?(view, "[data-testid=replaces-cart-note]", "Replaces the 3 bouquets")
    end

    test "tells a subscriber they already have one", %{conn: conn, product: product, variant: variant} do
      user = generate(admin_user(admin: false)) |> with_token()

      generate(subscription(user_id: user.id, product_variant_id: variant.id))

      conn = AshAuthentication.Plug.Helpers.store_in_session(conn, user)
      {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")
      view |> form("[data-testid=product-form]", %{subscribe: "true"}) |> render_change()

      assert has_element?(view, ~s|[data-testid=already-subscribed] a[href="/account"]|)
    end

    test "says before the click that a subscription can't join other products", %{
      conn: conn,
      product: product,
      order: order
    } do
      other = generate(product(draft: false))
      other_variant = generate(product_variant(product_id: other.id))
      Orders.add_line_item!(order.id, other_variant.id, 1, authorize?: false)
      {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")
      view |> form("[data-testid=product-form]", %{subscribe: "true"}) |> render_change()

      assert has_element?(view, "[data-testid=blocked-note]", "checked out on its own")
      refute has_element?(view, "[data-testid=add-to-cart-button][type=submit]")
    end
  end

  describe "photos" do
    test "a product with one photo shows no thumbnails", %{conn: conn} do
      product = generate(product(draft: false))
      generate(product_variant(product_id: product.id))

      {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")

      refute has_element?(view, "[data-testid=product-photos]")
    end

    test "a thumbnail swaps the photo without changing the size", %{conn: conn} do
      product = generate(product(draft: false, photo_slugs: ["a.jpg", "b.jpg"]))
      generate(product_variant(product_id: product.id, size: :small, price: "40.00"))
      generate(product_variant(product_id: product.id, size: :large, price: "60.00"))

      {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")
      assert has_element?(view, ~s|[data-testid=product-photos] button[aria-pressed=true]|, "Photo 1")

      view |> element("[data-testid=product-photos] button", "Photo 2") |> render_click()

      assert has_element?(view, ~s|[data-testid=product-image][src*="b.jpg"]|)
      assert has_element?(view, ~s|[data-testid=product-photos] button[aria-pressed=true]|, "Photo 2")
      assert has_element?(view, "[data-testid=variant-option-small][checked]")
      assert has_element?(view, "[data-testid=product-price]", "40")
    end

    test "choosing a size shows its photo, or the main photo without one", %{conn: conn} do
      product = generate(product(draft: false, photo_slugs: ["a.jpg", "b.jpg"]))
      small = generate(product_variant(product_id: product.id, size: :small, price: "40.00", own_photo_slug: "b.jpg"))
      large = generate(product_variant(product_id: product.id, size: :large, price: "60.00"))

      {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")

      view |> form("[data-testid=product-form]", %{product_variant_id: small.id}) |> render_change()
      assert has_element?(view, ~s|[data-testid=product-image][src*="b.jpg"]|)

      view |> form("[data-testid=product-form]", %{product_variant_id: large.id}) |> render_change()
      assert has_element?(view, ~s|[data-testid=product-image][src*="a.jpg"]|)
    end

    test "a hidden photo has no thumbnail but still shows for its size", %{conn: conn} do
      product = generate(product(draft: false, photo_slugs: ["a.jpg", "b.jpg", "c.jpg"], hidden_photo_slugs: ["b.jpg"]))
      small = generate(product_variant(product_id: product.id, size: :small, price: "40.00", own_photo_slug: "b.jpg"))
      generate(product_variant(product_id: product.id, size: :large, price: "60.00"))

      {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")

      assert has_element?(view, "[data-testid=product-photos] button", "Photo 2")
      refute has_element?(view, "[data-testid=product-photos] button", "Photo 3")
      refute has_element?(view, ~s|[data-testid=product-photos] img[src*="b.jpg"]|)

      view |> form("[data-testid=product-form]", %{product_variant_id: small.id}) |> render_change()
      assert has_element?(view, ~s|[data-testid=product-image][src*="b.jpg"]|)
    end
  end

  test "an unknown product is a 404", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/en/product/#{Ash.UUID.generate()}") end
    assert_error_sent 404, fn -> get(conn, ~p"/en/product/not-a-uuid") end
  end

  test "an ordinary product offers no subscription", %{conn: conn} do
    product = generate(product(draft: false))
    generate(product_variant(product_id: product.id))

    {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")

    refute has_element?(view, "[data-testid=product-subscribable]")
    refute has_element?(view, "[data-testid=subscribe-option]")
    refute has_element?(view, "[data-testid=subscription-faq]")
  end

  test "says why an add to the cart was refused", %{conn: conn, order: order} do
    product = generate(product(draft: false))
    variant = generate(product_variant(product_id: product.id))
    {:ok, view, _html} = live(conn, ~p"/en/product/#{product.id}")

    render_change(view, "change", %{product_variant_id: variant.id, subscribe: "true", interval_weeks: "2"})
    render_submit(view, "submit", %{})

    assert render(view) =~ "This product can&#39;t be subscribed to"
    assert line_items(order) == []
  end

  test "the store marks a subscribable product", %{conn: conn} do
    category = generate(product_category(slug: "bouquets", visibility: :public))
    product = generate(product(product_category_id: category.id, subscribable: true, free_delivery: true, draft: false))
    generate(product_variant(product_id: product.id, draft: false))

    {:ok, view, _html} = live(conn, ~p"/en/store/bouquets")

    assert has_element?(view, "#store-products", "Subscription")
  end

  defp line_items(order) do
    Ash.read!(LineItem, authorize?: false) |> Enum.filter(&(&1.order_id == order.id))
  end

  test "states the price range and stock to search engines", %{conn: conn} do
    product = generate(product(draft: false))
    generate(product_variant(product_id: product.id, size: :small, price: "40.00", stock_quantity: 0))
    generate(product_variant(product_id: product.id, size: :large, price: "60.00"))

    json_ld = conn |> get(~p"/en/product/#{product.id}") |> html_response(200) |> json_ld()

    assert %{"@type" => "Product", "name" => name, "offers" => offers} = json_ld
    assert name == product.name

    assert offers == %{
             "@type" => "AggregateOffer",
             "lowPrice" => "40.00",
             "highPrice" => "60.00",
             "offerCount" => 2,
             "priceCurrency" => "EUR",
             "availability" => "https://schema.org/InStock"
           }
  end

  defp json_ld(html) do
    case Regex.run(~r|<script type="application/ld\+json">(.*?)</script>|s, html) do
      [_, json] -> Jason.decode!(json)
      nil -> nil
    end
  end
end
