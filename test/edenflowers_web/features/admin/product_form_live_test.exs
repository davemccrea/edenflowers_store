defmodule EdenflowersWeb.Admin.ProductFormLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator
  import Mox

  alias Edenflowers.Catalog.Product

  setup :log_in_admin

  test "creates a product with two sizes", %{conn: conn} do
    category = generate(product_category())
    tax_rate = generate(tax_rate())

    {:ok, view, _html} = live(conn, ~p"/admin/products/new")

    view |> element("button", "Add size") |> render_click()
    upload_photos(view, ["rose.jpg"])

    assert {:error, {:live_redirect, %{to: "/admin/products/" <> _id}}} =
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
    assert ["local:///uploads/" <> _] = product.photo_slugs
    assert Enum.all?(product.product_variants, &is_nil(&1.own_photo_slug))
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

  test "sets a size's stock, and clearing it makes the size unlimited", %{conn: conn} do
    product = generate(product())
    variant = generate(product_variant(product_id: product.id, stock_quantity: 5))

    {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}")
    view |> form("#product-form", form: %{product_variants: %{"0" => %{stock_quantity: "10"}}}) |> render_submit()
    assert Ash.get!(Edenflowers.Catalog.ProductVariant, variant.id, authorize?: false).stock_quantity == 10

    {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}")
    view |> form("#product-form", form: %{product_variants: %{"0" => %{stock_quantity: ""}}}) |> render_submit()
    assert Ash.get!(Edenflowers.Catalog.ProductVariant, variant.id, authorize?: false).stock_quantity == nil
  end

  test "a size's details follow the category's product type", %{conn: conn} do
    cards = generate(product_category(product_type: :card))
    flowers = generate(product_category(product_type: :flowers))
    product = generate(product(product_category_id: flowers.id))
    variant = generate(product_variant(product_id: product.id, height_cm: "40", stem_count: "12"))

    {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}")
    assert has_element?(view, "#form_product_variants_0_stem_count[value=\"12\"]")

    view |> form("#product-form", form: %{product_category_id: cards.id}) |> render_change()
    refute has_element?(view, "#form_product_variants_0_stem_count")

    view
    |> form("#product-form", form: %{product_variants: %{"0" => %{dimensions_cm: "10 × 15"}}})
    |> render_submit()

    assert Ash.get!(Edenflowers.Catalog.ProductVariant, variant.id, authorize?: false).dimensions_cm == "10 × 15"
  end

  test "marks every size sold out in one go, keeping other unsaved edits", %{conn: conn} do
    product = generate(product())
    small = generate(product_variant(product_id: product.id, size: :small, stock_quantity: 4))
    large = generate(product_variant(product_id: product.id, size: :large))

    {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}")

    view |> form("#product-form", form: %{name: "Christmas wreath"}) |> render_change()
    view |> element("[data-testid=mark-sold-out]") |> render_click()
    view |> form("#product-form") |> render_submit()

    assert Ash.get!(Edenflowers.Catalog.ProductVariant, small.id, authorize?: false).stock_quantity == 0
    assert Ash.get!(Edenflowers.Catalog.ProductVariant, large.id, authorize?: false).stock_quantity == 0
    assert Ash.get!(Product, product.id, authorize?: false).name == "Christmas wreath"
  end

  test "adding and removing sizes in any order never needs a photo upload", %{conn: conn} do
    product = generate(product(photo_slugs: ["a.jpg", "b.jpg"]))
    generate(product_variant(product_id: product.id))
    generate(product_variant(product_id: product.id))

    {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}")

    sizes = Map.new(~w(0 1 2), &{&1, %{"price" => "30"}})
    render_change(view, "validate", %{"form" => %{"product_variants" => sizes}})
    view |> element(~s|button[phx-value-path="form[product_variants][0]"]|) |> render_click()
    view |> element("button", "Add size") |> render_click()
    view |> element(~s|button[phx-value-path="form[product_variants][1]"]|) |> render_click()
    view |> element("button", "Add size") |> render_click()

    assert has_element?(view, "input[type=radio][name='form[product_variants][2][own_photo_slug]']")
  end

  test "makes a photo main, removes one, and lets a size pick another", %{conn: conn} do
    product = generate(product(photo_slugs: ["a.jpg", "b.jpg", "c.jpg"]))
    variant = generate(product_variant(product_id: product.id, own_photo_slug: "a.jpg"))

    {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}")

    view |> element(~s|button[phx-click=make_main_photo][phx-value-slug="c.jpg"]|) |> render_click()
    view |> element(~s|button[phx-click=remove_photo][phx-value-slug="a.jpg"]|) |> render_click()

    # The size's photo is gone, so it shows as the main photo.
    assert has_element?(view, ~s|input[name="form[product_variants][0][own_photo_slug]"][value=""][checked]|)

    view
    |> form("#product-form", form: %{product_variants: %{"0" => %{own_photo_slug: "b.jpg"}}})
    |> render_submit()

    assert Ash.get!(Product, product.id, authorize?: false).photo_slugs == ["c.jpg", "b.jpg"]
    assert Ash.get!(Edenflowers.Catalog.ProductVariant, variant.id, authorize?: false).own_photo_slug == "b.jpg"
  end

  test "hides a size's photo picker while the product has one photo", %{conn: conn} do
    product = generate(product(photo_slugs: ["a.jpg", "b.jpg"]))
    generate(product_variant(product_id: product.id))

    {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}")

    radio = ~s|input[type=radio][name="form[product_variants][0][own_photo_slug]"]|
    assert has_element?(view, radio <> ~s|[value=""][checked]|)
    refute has_element?(view, radio <> ~s|[value="a.jpg"]|)

    view |> element(~s|button[phx-click=remove_photo][phx-value-slug="b.jpg"]|) |> render_click()

    refute has_element?(view, radio)
  end

  test "hides a photo from the store's gallery and shows it again", %{conn: conn} do
    product = generate(product(photo_slugs: ["a.jpg", "b.jpg", "c.jpg"]))
    generate(product_variant(product_id: product.id, size: :large, own_photo_slug: "b.jpg"))

    {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}")

    refute has_element?(view, ~s|button[phx-click=toggle_photo_hidden][phx-value-slug="a.jpg"]|)
    view |> element(~s|button[phx-click=toggle_photo_hidden][phx-value-slug="b.jpg"]|) |> render_click()
    view |> element(~s|button[phx-click=toggle_photo_hidden][phx-value-slug="c.jpg"]|) |> render_click()

    assert has_element?(view, ~s|button[phx-value-slug="c.jpg"][aria-label="Show photo 3 in the store's gallery"]|)

    view |> form("#product-form") |> render_submit()
    assert Ash.get!(Product, product.id, authorize?: false).hidden_photo_slugs == ["b.jpg", "c.jpg"]

    {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}")
    view |> element(~s|button[phx-click=toggle_photo_hidden][phx-value-slug="b.jpg"]|) |> render_click()
    view |> element(~s|button[phx-click=toggle_photo_hidden][phx-value-slug="c.jpg"]|) |> render_click()
    view |> form("#product-form") |> render_submit()

    assert Ash.get!(Product, product.id, authorize?: false).hidden_photo_slugs == []
  end

  test "keeps uploaded photos when the first save fails validation", %{conn: conn} do
    category = generate(product_category())
    tax_rate = generate(tax_rate())

    {:ok, view, _html} = live(conn, ~p"/admin/products/new")
    upload_photos(view, ["rose.jpg", "rose-side.jpg"])

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

    [product] = Ash.read!(Product, authorize?: false)
    assert Enum.map(product.photo_slugs, &uploaded_content/1) == ["rose.jpg", "rose-side.jpg"]
  end

  test "a size without its own photo shows the main photo", %{conn: conn} do
    category = generate(product_category())
    tax_rate = generate(tax_rate())

    {:ok, view, _html} = live(conn, ~p"/admin/products/new")

    upload_photos(view, ["rose.jpg"])

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

    [product] = Ash.read!(Product, authorize?: false, load: [:main_photo_slug, product_variants: [:photo_slug]])
    assert [%{own_photo_slug: nil, photo_slug: slug}] = product.product_variants
    assert slug == product.main_photo_slug
  end

  test "the Published and Visible toggles save as the opposite of draft", %{conn: conn} do
    product = generate(product(draft: false))
    visible = generate(product_variant(product_id: product.id, size: :small, price: "40.00", draft: false))
    hidden = generate(product_variant(product_id: product.id, size: :large, price: "60.00", draft: true))

    {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}")
    assert has_element?(view, ~s|input[type=checkbox][name="form[draft]"][checked]|)
    view |> form("#product-form") |> render_submit()

    refute Ash.get!(Product, product.id, authorize?: false).draft
    refute Ash.get!(Edenflowers.Catalog.ProductVariant, visible.id, authorize?: false).draft
    assert Ash.get!(Edenflowers.Catalog.ProductVariant, hidden.id, authorize?: false).draft
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
    expect(Edenflowers.External.ClaudeAPI.Mock, :translate, fn %{"name" => "Röda rosor"}, "sv-FI" ->
      {:ok,
       %{
         "en-GB" => %{"name" => "Red roses", "description" => ""},
         "fi" => %{"name" => "Punaiset ruusut", "description" => ""}
       }}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/products/new")

    view |> form("#product-form", form: %{translations: %{"sv-FI": %{name: "Röda rosor"}}}) |> render_change()
    view |> element("button[phx-value-from='sv-FI']") |> render_click()
    html = render_async(view, 500)

    assert html =~ "Red roses"
    assert html =~ "Punaiset ruusut"
  end

  test "marks a language tab missing its name or description", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/products/new")

    view
    |> form("#product-form",
      form: %{name: "Roses", description: "Red.", translations: %{"sv-FI": %{name: "Rosor", description: "Röda."}}}
    )
    |> render_change()

    refute has_element?(view, "#language-tab-en-GB .status")
    refute has_element?(view, "#language-tab-sv-FI .status")
    assert has_element?(view, "#language-tab-fi .status")
  end

  defp upload_photos(view, names) do
    # Each file's content is its name, so a test can tell stored photos apart.
    files = for name <- names, do: %{name: name, content: name, type: "image/jpeg"}
    upload = file_input(view, "#product-form", :photos, files)
    for name <- names, do: render_upload(upload, name)
  end

  defp uploaded_content("local:///uploads/" <> filename),
    do: File.read!(Path.join(Application.fetch_env!(:edenflowers, :uploads_dir), filename))
end
