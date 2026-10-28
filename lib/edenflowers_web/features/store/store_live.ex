defmodule EdenflowersWeb.Store.StoreLive do
  @moduledoc """
  Public catalogue page for browsing products by category.
  """

  use EdenflowersWeb, :live_view

  alias Edenflowers.Catalog
  alias Edenflowers.Translations

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(_params, _session, socket) do
    categories = Catalog.list_categories!()
    # Found before translating, as translation replaces the English slug.
    bouquets_id = Enum.find_value(categories, &(&1.slug == "bouquets" && &1.id))
    categories = Translations.translate(categories)
    bouquets = Enum.find(categories, &(&1.id == bouquets_id))

    {:ok,
     assign(socket,
       alternates: alternates("/#{language}/store"),
       categories: categories,
       bouquets: bouquets,
       products: [],
       free_dist_km: Edenflowers.Fulfillment.free_dist_km(),
       selected_category: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case Map.get(params, "category") do
      nil ->
        show_bouquets(socket)

      category_slug ->
        case load_products(category_slug) do
          {:ok, products, selected_category, alternates} ->
            {:noreply,
             assign(socket,
               alternates: alternates,
               page_title: ~t"#{category = selected_category.name} in Vaasa",
               page_description: selected_category.description,
               products: products,
               selected_category: selected_category
             )}

          :error ->
            raise Ash.Error.Query.NotFound, resource: Catalog.ProductCategory
        end
    end
  end

  defp show_bouquets(%{assigns: %{bouquets: nil}} = socket),
    do: {:noreply, assign(socket, page_title: ~t"Store", products: [], selected_category: nil)}

  defp show_bouquets(socket),
    do: {:noreply, push_patch(socket, to: ~q"/#{language}/store/#{socket.assigns.bouquets.slug}", replace: true)}

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :other_categories?,
        Enum.any?(assigns.categories, fn category ->
          is_nil(assigns.selected_category) or category.id != assigns.selected_category.id
        end)
      )

    ~H"""
    <Layouts.app
      current_user={@current_user}
      order={@order}
      flash={@flash}
      current_path={@current_path}
      alternates={@alternates}
    >
      <.container>
        <h1 class="page-title mb-4">
          {if @selected_category, do: @selected_category.name, else: ~t"Store"}
        </h1>
        <p
          :if={@selected_category && @selected_category.description}
          class="font-serif text-base-content/85 max-w-[48ch] text-lg italic"
        >
          {@selected_category.description}
        </p>

        <nav :if={@categories != []} aria-label={~t"Categories"} class="mt-8 mb-12 md:mb-16">
          <ol class="category-index [scrollbar-width:none] m-0 flex list-none gap-x-8 overflow-x-auto whitespace-nowrap p-0">
            <li :for={category <- @categories}>
              <.link
                patch={~q"/#{language}/store/#{category.slug}"}
                class="category-index__link text-base-content touch-target block py-2 no-underline"
                aria-current={@selected_category && @selected_category.id == category.id && "page"}
              >
                <span class="category-index__name font-serif text-lg md:text-xl">{category.name}</span>
              </.link>
            </li>
          </ol>
        </nav>

        <div id="store-products">
          <%= if Enum.empty?(@products) do %>
            <div class="bg-cream flex flex-col items-center gap-5 px-8 py-20 text-center sm:py-24">
              <.flower name="flower-42" class="text-primary/80 h-20 w-20" />
              <h2 class="section-title text-primary">{~t"Nothing listed here just now"}</h2>
              <p class="text-base-content/75 max-w-md leading-relaxed">
                <%= if @other_categories? do %>
                  {~t"Browse another collection, or get in touch to ask about flowers for your occasion."}
                <% else %>
                  {~t"Need flowers before then? Get in touch and I'll gladly help."}
                <% end %>
              </p>
              <div class="mt-2 flex flex-wrap justify-center gap-3">
                <.button
                  :if={@selected_category && @bouquets && @selected_category.id != @bouquets.id}
                  patch={~q"/#{language}/store/#{@bouquets.slug}"}
                  variant="primary"
                >
                  {~t"Browse bouquets"}
                </.button>
                <.button navigate={~q"/#{language}/contact"} variant="secondary">
                  {~t"Get in touch"}
                </.button>
              </div>
            </div>
          <% else %>
            <.free_delivery_note
              :if={@free_dist_km && Enum.any?(@products, & &1.free_delivery)}
              free_dist_km={@free_dist_km}
              class="mb-8"
            />
            <ul
              class="grid gap-x-6 gap-y-16 md:grid-cols-2 md:gap-y-20 xl:grid-cols-3 xl:gap-x-8"
              role="list"
            >
              <li :for={product <- @products}>
                <.product_card
                  product={product}
                  navigate={~q"/#{language}/product/#{product}"}
                  locale={Edenflowers.Format.locale()}
                  heading="h2"
                  free_dist_km={@free_dist_km}
                />
              </li>
            </ul>
          <% end %>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  defp load_products(category_slug) do
    case Catalog.get_category_by_slug(category_slug) do
      {:ok, category} ->
        products = category.id |> Catalog.list_products_by_category!() |> Translations.translate()
        {:ok, products, Translations.translate(category), alternates("/#{language}/store/#{category.slug}")}

      {:error, _} ->
        :error
    end
  end
end
