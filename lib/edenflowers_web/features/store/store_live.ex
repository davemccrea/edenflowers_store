defmodule EdenflowersWeb.Store.StoreLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Catalog
  alias Edenflowers.Translations

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    categories =
      Catalog.list_categories!()
      |> Translations.translate()
      |> Enum.with_index(1)

    {:ok, assign(socket, categories: categories, products: [], selected_category: nil)}
  end

  def handle_params(params, _uri, socket) do
    case Map.get(params, "category") do
      nil ->
        {:noreply, push_patch(socket, to: ~p"/store/bouquets", replace: true)}

      category_slug ->
        case load_products(category_slug) do
          {:ok, products, selected_category} ->
            {:noreply, assign(socket, products: products, selected_category: selected_category)}

          :error when category_slug == "bouquets" ->
            {:noreply, assign(socket, products: [], selected_category: nil)}

          :error ->
            {:noreply, push_patch(socket, to: ~p"/store/bouquets", replace: true)}
        end
    end
  end

  defp load_products(category_slug) do
    case Catalog.get_category_by_slug(category_slug) do
      {:ok, category} ->
        products = category.id |> Catalog.list_products_by_category!() |> Translations.translate()
        {:ok, products, Translations.translate(category)}

      {:error, _} ->
        :error
    end
  end

  def render(assigns) do
    assigns =
      assign(
        assigns,
        :other_categories?,
        Enum.any?(assigns.categories, fn {category, _idx} ->
          is_nil(assigns.selected_category) or category.id != assigns.selected_category.id
        end)
      )

    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <h1 class="page-title mb-12 md:mb-16">
          {if @selected_category, do: @selected_category.name, else: ~t"Store"}
        </h1>

        <nav :if={@categories != []} aria-label={~t"Categories"} class="mb-20 md:mb-28">
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
                class="category-index__link grid-cols-[auto_1fr] text-base-content group grid items-baseline gap-x-3.5 no-underline"
                aria-current={@selected_category && @selected_category.id == category.id && "page"}
              >
                <span
                  class="eyebrow text-base-content/70 [font-variant-numeric:tabular-nums] self-center"
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
            <div class="bg-cream flex flex-col items-center gap-5 px-8 py-20 text-center sm:py-24">
              <.flower name="flower-42" class="text-primary/80 h-20 w-20" />
              <h2 class="section-title text-primary">{~t"I'm preparing the next collection"}</h2>
              <p class="text-base-content/75 max-w-md leading-relaxed">
                <%= if @other_categories? do %>
                  {~t"Check back soon, or browse another collection in the meantime."}
                <% else %>
                  {~t"Need flowers before then? Get in touch and I'll gladly help."}
                <% end %>
              </p>
              <.button
                :if={@selected_category && @selected_category.slug != "bouquets"}
                patch={~p"/store/bouquets"}
                variant="secondary"
                class="mt-2"
              >
                {~t"Browse bouquets"}
              </.button>
              <.button
                :if={!@other_categories?}
                navigate={~p"/contact"}
                variant="secondary"
                class="mt-2"
              >
                {~t"Get in touch"}
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
                  locale={Edenflowers.Format.locale()}
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
