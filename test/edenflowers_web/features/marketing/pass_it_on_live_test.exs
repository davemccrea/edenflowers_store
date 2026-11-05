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
    valid_until = Edenflowers.ShopTime.today() |> Date.add(30) |> Edenflowers.Format.date("en")
    assert has_element?(view, "#pass-it-on-code", "Valid until #{valid_until}")
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

  test "a card linked to its gift order greets the recipient by first name", %{conn: conn} do
    [code] = Edenflowers.Pricing.create_pass_it_on_batch!("Skicka vidare", 1, actor: Edenflowers.Actors.system_actor())
    {:ok, card} = Edenflowers.Pricing.get_promotion_by_code(code)
    gift = placed_order(gift: true, recipient_name: "Anna Virtanen")
    Edenflowers.Pricing.link_card_to_gift_order!(card, gift.id, actor: generate(admin_user()))

    {:ok, view, _html} = live(conn, "/en/pass-it-on?code=#{code}")
    assert has_element?(view, "#main-content", "Hi Anna! Someone thought of you today.")
  end
end
