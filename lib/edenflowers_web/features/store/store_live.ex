defmodule EdenflowersWeb.Store.StoreLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Catalog.{Product, ProductCategory}

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    locale = current_locale_atom()

    categories =
      ProductCategory.get_all!()
      |> Ash.load!(:translations)
      |> Enum.map(&AshTranslation.translate(&1, locale))
      |> Enum.with_index(1)

    {:ok, assign(socket, categories: categories, products: [], selected_category: nil)}
  end

  def handle_params(params, _uri, socket) do
    case Map.get(params, "category") do
      nil ->
        {:noreply, push_patch(socket, to: ~p"/store/bouquets")}

      category_slug ->
        case load_products(category_slug) do
          {:ok, products, selected_category} ->
            {:noreply, assign(socket, products: products, selected_category: selected_category)}

          :error ->
            {:noreply, push_patch(socket, to: ~p"/store/bouquets")}
        end
    end
  end

  defp load_products(category_slug) do
    case ProductCategory.get_by_slug(category_slug) do
      {:ok, category} ->
        translated_category = AshTranslation.translate(category, current_locale_atom())
        {:ok, Product.get_by_category!(category.id), translated_category}

      {:error, _} ->
        :error
    end
  end

  defp current_locale_atom, do: Localize.get_locale().cldr_locale_id

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <p class="eyebrow text-base-content/60 mb-5">{~t"The Store"}</p>
        <h1 :if={@selected_category} class="page-title mb-12 md:mb-16">{@selected_category.name}</h1>

        <nav aria-label={~t"Categories"} class="mb-20 md:mb-28">
          <ol class="m-0 grid list-none grid-cols-1 gap-6 p-0 md:grid-cols-3 md:gap-10">
            <li
              :for={{category, idx} <- @categories}
              id={"category-item-#{category.id}"}
              class="category-index__item"
              data-active={@selected_category && @selected_category.id == category.id && "true"}
            >
              <.link
                id={"category-link-#{category.id}"}
                patch={~p"/store/#{category.slug}"}
                phx-click={
                  JS.set_attribute({"data-active", "true"}, to: "#category-item-#{category.id}")
                  |> JS.remove_attribute("data-active", to: ".category-index__item:not(#category-item-#{category.id})")
                  |> JS.set_attribute({"aria-current", "page"}, to: "#category-link-#{category.id}")
                  |> JS.remove_attribute("aria-current", to: ".category-index__link:not(#category-link-#{category.id})")
                }
                class="category-index__link grid-cols-[auto_1fr] text-base-content group grid items-baseline gap-x-3.5 no-underline outline-none"
                aria-current={@selected_category && @selected_category.id == category.id && "page"}
              >
                <span
                  class="eyebrow text-base-content/55 [font-variant-numeric:tabular-nums] self-center"
                  aria-hidden="true"
                >
                  {String.pad_leading(Integer.to_string(idx), 2, "0")}
                </span>
                <span class="category-index__name font-serif w-max max-w-full text-xl leading-snug tracking-normal md:text-2xl">
                  {category.name}
                </span>
                <span class="font-serif text-base-content/85 max-w-[32ch] col-start-2 pt-2.5 italic">
                  {category.description}
                </span>
              </.link>
            </li>
          </ol>
        </nav>

        <div id="store-products">
          <%= if Enum.empty?(@products) do %>
            <div class="bg-cream flex flex-col items-center gap-5 rounded-lg px-8 py-20 text-center sm:py-24">
              <.flower name="flower-42" class="text-primary/80 h-20 w-20" />
              <h3 class="section-title text-primary">{~t"Fresh stems on the way"}</h3>
              <p class="text-base-content/75 max-w-md leading-relaxed">
                {~t"This collection is being refreshed. Check back shortly — or browse another category in the meantime."}
              </p>
              <.button patch={~p"/store/bouquets"} variant="secondary" class="mt-2">
                {~t"Browse bouquets"}
              </.button>
            </div>
          <% else %>
            <ul
              class="grid gap-x-6 gap-y-16 md:grid-cols-2 md:gap-y-20 xl:grid-cols-3 xl:gap-x-8"
              role="list"
            >
              <li :for={product <- @products}>
                <.product_card
                  product={product}
                  navigate={~p"/product/#{product}"}
                  locale={Localize.get_locale().cldr_locale_id |> to_string()}
                />
              </li>
            </ul>
          <% end %>
        </div>
      </.container>
    </Layouts.app>
    """
  end
end
