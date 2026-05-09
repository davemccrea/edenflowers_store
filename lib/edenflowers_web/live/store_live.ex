defmodule EdenflowersWeb.StoreLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Store.{Product, ProductCategory}

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  def mount(params, _session, socket) do
    locale = current_locale_atom()

    categories =
      ProductCategory.get_all!()
      |> Ash.load!(:translations)
      |> Enum.map(&AshTranslation.translate(&1, locale))

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
        translated_category = AshTranslation.translate(category, current_locale_atom())

        {Product.get_by_category!(category.id), translated_category}

      {:error, _} ->
        # If invalid slug, redirect to bouquets will happen on next mount
        {[], nil}
    end
  end

  defp current_locale_atom, do: Localize.get_locale().cldr_locale_id

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <.breadcrumb>
          <:item navigate={~p"/"} label={~t"Home"} />
          <:item navigate={~p"/store"} label={~t"Store"} />
          <:item label={@selected_category.name} />
        </.breadcrumb>

        <div class="mb-10 max-w-2xl">
          <h1 class="page-title text-base-content mb-3">
            {@selected_category.name}
          </h1>
          <p class="text-base-content/70 leading-relaxed sm:text-lg">
            {@selected_category.description}
          </p>
        </div>

        <nav aria-label={~t"Categories"} class="mb-10 flex flex-wrap gap-3">
          <.button
            :for={category <- @categories}
            navigate={~p"/store/#{category.slug}"}
            variant={if(@selected_category.id == category.id, do: "primary", else: nil)}
            aria-current={@selected_category.id == category.id && "page"}
          >
            {category.name}
          </.button>
        </nav>

        <%= if Enum.empty?(@products) do %>
          <div class="bg-pastel-3 flex flex-col items-center gap-5 rounded-lg px-8 py-20 text-center sm:py-24">
            <.icon name="hero-sparkles" class="text-primary/80 h-10 w-10" />
            <h3 class="section-title text-primary">{~t"Fresh stems on the way"}</h3>
            <p class="text-base-content/75 max-w-md leading-relaxed">
              {~t"We're refreshing this collection right now. Check back shortly — or browse another category in the meantime."}
            </p>
            <.button navigate={~p"/store/bouquets"} variant="secondary" class="mt-2">
              {~t"Browse bouquets"}
            </.button>
          </div>
        <% else %>
          <ul class="grid gap-6 sm:grid-cols-2 xl:grid-cols-3 xl:gap-8" role="list">
            <li
              :for={product <- @products}
              class="group border-base-300/70 bg-base-100 relative flex flex-col overflow-hidden rounded-lg border focus-within:border-primary/60 focus-within:shadow-lg hover:border-primary/50 hover:shadow-lg"
            >
              <.link
                class="flex h-full flex-col focus:outline-none"
                navigate={~p"/product/#{product}"}
              >
                <figure class="aspect-square relative overflow-hidden">
                  <img
                    src={product.image_slug |> Imgproxy.new() |> Imgproxy.resize(600, 600, type: "fill") |> to_string()}
                    alt=""
                    class="h-full w-full object-cover transition duration-700 ease-out group-hover:scale-[1.03]"
                    width="1"
                    height="1"
                    loading="lazy"
                  />
                </figure>

                <div class="flex flex-1 flex-col gap-2 px-5 py-5 sm:px-6 sm:py-6">
                  <h3 class="card-title text-base-content link-underline-group-hover-display">
                    {product.name}
                  </h3>

                  <div class="text-base-content/70 text-sm">
                    {Edenflowers.Utils.format_money(product.cheapest_price)}
                  </div>
                </div>
              </.link>
            </li>
          </ul>
        <% end %>
      </.container>
    </Layouts.app>
    """
  end
end
