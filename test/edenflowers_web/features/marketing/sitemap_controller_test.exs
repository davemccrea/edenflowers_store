defmodule EdenflowersWeb.Marketing.SitemapControllerTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator

  test "lists every language of the public pages and store products, not drafts", %{conn: conn} do
    category = generate(product_category(visibility: :public))
    product = generate(product(product_category_id: category.id, draft: false))
    generate(product_variant(product_id: product.id))
    draft = generate(product(product_category_id: category.id, draft: true))
    generate(product_variant(product_id: draft.id))

    xml = conn |> get(~p"/sitemap.xml") |> response(200)

    assert xml =~ "<loc>http://localhost:4002/en/weddings</loc>"
    assert xml =~ "<loc>http://localhost:4002/fi/haat</loc>"
    assert xml =~ "<loc>http://localhost:4002/sv/brollop</loc>"
    assert xml =~ "/fi/kauppa/#{category.slug}</loc>"
    assert xml =~ "/sv/produkt/#{product.id}</loc>"
    refute xml =~ draft.id
  end
end
