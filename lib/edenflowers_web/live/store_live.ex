defmodule EdenflowersWeb.StoreLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Store.{Product, ProductCategory}

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  def mount(params, _session, socket) do
    categories = ProductCategory.get_all!()
    category_slug = Map.get(params, "category")

    # Redirect to bouquets if no category is specified
    if is_nil(category_slug) do
      {:ok, push_navigate(socket, to: ~p"/store/bouquets")}
    else
      {products, selected_category} = load_products(category_slug)

      {:ok,
       assign(socket,
         products: products,
         categories: categories,
         selected_category: selected_category
       )}
    end
  end

  defp load_products(category_slug) do
    case ProductCategory.get_by_slug(category_slug) do
      {:ok, category} ->
        {Product.get_by_category!(category.id), category}

      {:error, _} ->
        # If invalid slug, redirect to bouquets will happen on next mount
        {[], nil}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash}>
      <div class="container my-36">
        <.breadcrumb>
          <:item navigate={~p"/"} label={gettext("Home")} />
          <:item label={gettext("Store")} />
        </.breadcrumb>

        <div class="mb-12">
          <h1 class="font-serif text-base-content mb-2 text-4xl">
            <%= if @selected_category do %>
              {@selected_category.name}
            <% else %>
              {gettext("All arrangements")}
            <% end %>
          </h1>
          <p class="text-base-content/60 text-sm sm:text-base">
            {gettext("Soft palettes, precise silhouettes, and seasonal stems curated by our studio team.")}
          </p>
        </div>

        <div class="mb-8">
          <div class="flex flex-wrap gap-3">
            <.button
              :for={category <- @categories}
              navigate={~p"/store/#{category.slug}"}
              variant={if(@selected_category && @selected_category.id == category.id, do: "primary", else: nil)}
            >
              {category.name}
            </.button>
          </div>
        </div>

        <%= if Enum.empty?(@products) do %>
          <div class="border-primary/40 bg-base-100 flex flex-col items-center gap-4 border border-dashed px-8 py-16 text-center">
            <.icon name="hero-sparkles" class="text-primary h-12 w-12" />
            <h3 class="font-serif text-2xl">{gettext("Fresh stems loading soon")}</h3>
            <p class="text-base-content/70 max-w-md text-sm sm:text-base">
              {gettext("We're refreshing our collection. Check back shortly for newly arranged bouquets ready to ship.")}
            </p>
          </div>
        <% else %>
          <ul class="grid gap-5 sm:grid-cols-2 xl:grid-cols-3 xl:gap-6" role="list">
            <li
              :for={product <- @products}
              class="group border-base-300/80 bg-base-100 relative flex flex-col overflow-hidden border transition duration-200 hover:border-primary/60 hover:shadow-lg"
            >
              <.link
                class="flex h-full flex-col"
                navigate={~p"/product/#{product}"}
                aria-labelledby={"product-#{product.id}"}
              >
                <figure class="aspect-square relative overflow-hidden">
                  <img
                    src={product.image_slug}
                    alt={product.name}
                    class="h-full w-full object-cover transition duration-300 group-hover:scale-[1.05]"
                    width="1"
                    height="1"
                    loading="lazy"
                  />
                </figure>

                <div class="flex flex-1 flex-col justify-between gap-2 px-5 pt-5 pb-5 sm:px-6 sm:pb-6">
                  <h3
                    id={"product-#{product.id}"}
                    class="font-serif text-base-content text-xl tracking-wide sm:text-2xl"
                  >
                    {product.name}
                  </h3>

                  <div class="text-base-content flex items-center justify-between">
                    <span class="text-base-content/70 text-sm sm:text-base">
                      {Edenflowers.Utils.format_money(product.cheapest_price)}
                    </span>
                    <span class="text-base-content/60 flex items-center gap-1 text-xs uppercase tracking-wider transition duration-200 group-hover:text-primary sm:text-sm">
                      {gettext("View")}
                      <.icon
                        name="hero-arrow-right"
                        class="h-4 w-4 transition-transform duration-150 ease-out group-hover:translate-x-1"
                      />
                    </span>
                  </div>
                </div>
              </.link>
            </li>
          </ul>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
