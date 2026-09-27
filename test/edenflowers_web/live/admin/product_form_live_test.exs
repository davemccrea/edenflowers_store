defmodule EdenflowersWeb.Admin.ProductFormLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator
  import Mox

  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Catalog.Product

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    %{conn: conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)}
  end

  test "creates a product with two sizes", %{conn: conn} do
    category = generate(product_category())
    tax_rate = generate(tax_rate())

    {:ok, view, _html} = live(conn, ~p"/admin/products/new")

    view |> element("button", "Add size") |> render_click()

    for name <-
          ~w(photo_form[image_slug] photo_form[product_variants][0][image_slug] photo_form[product_variants][1][image_slug]) do
      view |> file_input("#product-form", name, [photo()]) |> render_upload("rose.jpg")
    end

    assert {:error, {:live_redirect, %{to: "/admin/products"}}} =
             view
             |> form("#product-form",
               form: %{
                 name: "Rose bouquet",
                 description: "Roses.",
                 product_category_id: category.id,
                 tax_rate_id: tax_rate.id,
                 draft: "false",
                 product_variants: %{
                   "0" => %{size: "small", price: "40", draft: "false"},
                   "1" => %{size: "large", price: "60", draft: "false"}
                 }
               }
             )
             |> render_submit()

    [product] = Ash.read!(Product, authorize?: false, load: [:product_variants])
    assert product.name == "Rose bouquet"
    refute product.draft
    assert product.product_variants |> Enum.map(& &1.size) |> Enum.sort() == [:large, :small]
    assert String.starts_with?(product.image_slug, "local:///uploads/rose-")
    assert Enum.all?(product.product_variants, &String.starts_with?(&1.image_slug, "local:///uploads/rose-"))
  end

  test "edits a size's price without touching the others", %{conn: conn} do
    product = generate(product())
    small = generate(product_variant(product_id: product.id, size: :small, price: "40.00"))
    large = generate(product_variant(product_id: product.id, size: :large, price: "60.00"))

    {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}")

    view
    |> form("#product-form", form: %{product_variants: %{"0" => %{price: "45.00"}}})
    |> render_submit()

    assert Ash.get!(Edenflowers.Catalog.ProductVariant, small.id, authorize?: false).price == Decimal.new("45.00")
    assert Ash.get!(Edenflowers.Catalog.ProductVariant, large.id, authorize?: false).price == Decimal.new("60.00")
  end

  test "keeps uploaded photos when the first save fails validation", %{conn: conn} do
    category = generate(product_category())
    tax_rate = generate(tax_rate())

    {:ok, view, _html} = live(conn, ~p"/admin/products/new")

    for name <- ~w(photo_form[image_slug] photo_form[product_variants][0][image_slug]) do
      view |> file_input("#product-form", name, [photo()]) |> render_upload("rose.jpg")
    end

    fields = %{
      description: "Roses.",
      product_category_id: category.id,
      tax_rate_id: tax_rate.id,
      product_variants: %{"0" => %{price: "40"}}
    }

    view |> form("#product-form", form: fields) |> render_submit()
    assert render(view) =~ "is required"

    assert {:error, {:live_redirect, _}} =
             view |> form("#product-form", form: Map.put(fields, :name, "Rose bouquet")) |> render_submit()

    [product] = Ash.read!(Product, authorize?: false, load: [:product_variants])
    assert String.starts_with?(product.image_slug, "local:///uploads/rose-")
    assert [%{image_slug: "local:///uploads/rose-" <> _}] = product.product_variants
  end

  test "a new size without its own photo uses the product photo", %{conn: conn} do
    category = generate(product_category())
    tax_rate = generate(tax_rate())

    {:ok, view, _html} = live(conn, ~p"/admin/products/new")

    view |> file_input("#product-form", "photo_form[image_slug]", [photo()]) |> render_upload("rose.jpg")

    view
    |> form("#product-form",
      form: %{
        name: "Rose bouquet",
        description: "Roses.",
        product_category_id: category.id,
        tax_rate_id: tax_rate.id,
        product_variants: %{"0" => %{price: "40"}}
      }
    )
    |> render_submit()

    [product] = Ash.read!(Product, authorize?: false, load: [:product_variants])
    assert [%{image_slug: slug}] = product.product_variants
    assert slug == product.image_slug
  end

  test "removing a saved size archives it, keeping it on past orders", %{conn: conn} do
    product = generate(product(draft: false))
    kept = generate(product_variant(product_id: product.id, size: :small, price: "40.00", draft: false))
    removed = generate(product_variant(product_id: product.id, size: :large, price: "20.00", draft: false))
    order = generate(order())
    line_item = generate(line_item(order_id: order.id, product_variant_id: removed.id))

    {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}")

    # Sizes sort by price, so the cheaper removed one is the first row.
    view |> element(~s|button[phx-value-path="form[product_variants][0]"]|) |> render_click()
    view |> form("#product-form") |> render_submit()

    product = Ash.get!(Product, product.id, authorize?: false, load: [:product_variants, :cheapest_price])
    assert [%{id: kept_id}] = product.product_variants
    assert kept_id == kept.id
    assert product.cheapest_price == Decimal.new("40.00")

    refute Ash.get(Edenflowers.Catalog.ProductVariant, removed.id, authorize?: false) |> elem(0) == :ok
    assert Ash.get!(Edenflowers.Orders.LineItem, line_item.id, authorize?: false).product_variant_id == removed.id
  end

  test "fills the other languages from Swedish", %{conn: conn} do
    expect(Edenflowers.Claude.Mock, :translate, fn %{"name" => "Röda rosor"}, "sv-FI" ->
      {:ok,
       %{
         "en-GB" => %{"name" => "Red roses", "description" => ""},
         "fi" => %{"name" => "Punaiset ruusut", "description" => ""}
       }}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/products/new")

    view |> form("#product-form", form: %{translations: %{"sv-FI": %{name: "Röda rosor"}}}) |> render_change()
    view |> element("button[phx-value-from='sv-FI']") |> render_click()
    html = render_async(view)

    assert html =~ "Red roses"
    assert html =~ "Punaiset ruusut"
  end

  defp photo, do: %{name: "rose.jpg", content: "jpeg bytes", type: "image/jpeg"}
end
