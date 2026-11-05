defmodule EdenflowersWeb.Marketing.PassItOnLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  setup do
    bouquets = generate(product_category(slug: "bouquets", visibility: :public))
    product = generate(product(product_category_id: bouquets.id, draft: false, featured: true, name: "Peony dream"))
    generate(product_variant(product_id: product.id, draft: false))
    %{product: product}
  end

  test "a card's code goes on the cart, and the page offers Jennie's favourite with its discount", %{
    conn: conn,
    product: product
  } do
    [code] = Edenflowers.Pricing.create_pass_it_on_batch!("Skicka vidare", 1, actor: Edenflowers.Actors.system_actor())

    conn = get(conn, "/en/pass-it-on?code=#{code}")
    {:ok, view, _html} = live(conn)

    assert has_element?(view, "#pass-it-on-code", code)
    assert has_element?(view, "#pass-it-on-code", "already in your cart")
    assert has_element?(view, "#pass-it-on-code", "15% off")
    assert has_element?(view, ~s|a[href="/en/product/#{product.slug}"]|, "Send these flowers")
  end

  test "a used code shows the favourite without a discount", %{conn: conn, product: product} do
    used = generate(promotion(code: "USED01", usage_limit: 1))
    use_promotion(used)

    {:ok, view, _html} = live(conn, "/en/pass-it-on?code=USED01")

    refute has_element?(view, "#pass-it-on-code")
    assert has_element?(view, "#pass-it-on-code-unusable")
    refute has_element?(view, "#main-content", "% off")
    assert has_element?(view, ~s|a[href="/en/product/#{product.slug}"]|)
  end
end
