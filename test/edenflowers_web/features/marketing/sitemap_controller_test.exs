defmodule EdenflowersWeb.Marketing.SitemapControllerTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator

  test "lists public pages and store products, not drafts", %{conn: conn} do
    category = generate(product_category(visibility: :public))
    product = generate(product(product_category_id: category.id, draft: false))
    generate(product_variant(product_id: product.id))
    draft = generate(product(product_category_id: category.id, draft: true))
    generate(product_variant(product_id: draft.id))

    xml = conn |> get(~p"/sitemap.xml") |> response(200)

    assert xml =~ "<loc>http://localhost:4002/weddings</loc>"
    assert xml =~ "/store/#{category.slug}</loc>"
    assert xml =~ "/product/#{product.id}</loc>"
    refute xml =~ draft.id
  end
end
