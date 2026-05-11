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
      |> Enum.with_index(1)

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
        <p class="eyebrow text-base-content/60 mb-8 md:mb-12">{~t"The Store"}</p>
        <h1 class="sr-only">{~t"Store"}</h1>

        <nav aria-label={~t"Categories"} class="category-index mb-20 md:mb-28">
          <ol class="category-index__list">
            <li
              :for={{category, idx} <- @categories}
              class="category-index__item"
              data-active={@selected_category.id == category.id && "true"}
            >
              <.link
                navigate={~p"/store/#{category.slug}"}
                class="category-index__link group"
                aria-current={@selected_category.id == category.id && "page"}
              >
                <span class="category-index__numeral" aria-hidden="true">
                  {String.pad_leading(Integer.to_string(idx), 2, "0")}
                </span>
                <span class="category-index__name">{category.name}</span>
                <span class="category-index__description">{category.description}</span>
              </.link>
            </li>
          </ol>
        </nav>

        <%= if Enum.empty?(@products) do %>
          <div class="bg-cream flex flex-col items-center gap-5 rounded-lg px-8 py-20 text-center sm:py-24">
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
          <ul
            class="grid gap-x-6 gap-y-16 md:grid-cols-2 md:gap-y-20 xl:grid-cols-3 xl:gap-x-8"
            role="list"
          >
            <li :for={product <- @products}>
              <.product_card product={product} navigate={~p"/product/#{product}"} />
            </li>
          </ul>
        <% end %>
      </.container>
    </Layouts.app>
    """
  end
end
