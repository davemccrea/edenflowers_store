defmodule EdenflowersWeb.Marketing.SitemapControllerTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator

  test "lists published upcoming courses but leaves out drafts", %{conn: conn} do
    published = generate(course(draft: false))
    draft = generate(course(draft: true))

    xml = conn |> get(~p"/sitemap.xml") |> response(200)

    assert xml =~ "/en/courses/#{published.slug}</loc>"
    assert xml =~ "/fi/kurssit/#{published.slug}</loc>"
    assert xml =~ "/sv/kurser/#{published.slug}</loc>"
    refute xml =~ draft.slug
  end

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
    assert xml =~ "<loc>http://localhost:4002/en/terms</loc>"
    assert xml =~ "<loc>http://localhost:4002/fi/toimitusehdot</loc>"
    assert xml =~ "<loc>http://localhost:4002/sv/kopvillkor</loc>"
    assert xml =~ "/fi/kauppa/#{category.slug}</loc>"
    assert xml =~ "/sv/produkt/#{product.slug}</loc>"
    refute xml =~ draft.slug
  end
end
