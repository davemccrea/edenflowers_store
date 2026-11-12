defmodule Edenflowers.Catalog.ProductCategoryTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Catalog

  test "a public category is found by its slug" do
    bouquets = generate(product_category(slug: "bouquets", visibility: :public))
    generate(product_category(slug: "secret", visibility: :hidden))

    assert {:ok, %{id: id}} = Catalog.get_category_by_slug("bouquets")
    assert id == bouquets.id
    assert {:error, _} = Catalog.get_category_by_slug("secret")
  end

  describe "moving a category" do
    setup do
      %{admin: generate(admin_user())}
    end

    defp store_order(admin), do: Enum.map(Catalog.list_all_categories!(actor: admin), &{&1.name, &1.position})

    test "swaps it with its neighbour and numbers every category, also ones without a position", %{admin: admin} do
      generate(product_category(name: "Bouquets", position: 0))
      generate(product_category(name: "Plants", position: 3))
      wreaths = generate(product_category(name: "Wreaths", position: nil))
      generate(product_category(name: "Cards", position: nil))

      Catalog.move_category!(wreaths, :up, actor: admin)

      assert store_order(admin) == [{"Bouquets", 0}, {"Plants", 1}, {"Wreaths", 2}, {"Cards", 3}]
    end

    test "leaves the first category first when it is moved up", %{admin: admin} do
      bouquets = generate(product_category(name: "Bouquets", position: 0))
      generate(product_category(name: "Plants", position: 1))

      Catalog.move_category!(bouquets, :up, actor: admin)

      assert store_order(admin) == [{"Bouquets", 0}, {"Plants", 1}]
    end

    test "is refused without an admin" do
      bouquets = generate(product_category(name: "Bouquets"))

      assert {:error, %Ash.Error.Forbidden{}} = Catalog.move_category(bouquets, :down, actor: nil)
    end
  end
end
