defmodule EdenflowersWeb.Admin.ProductsLive do
  @moduledoc """
  Admin product list for finding and managing catalogue items.
  """

  use EdenflowersWeb, :live_view
  use Cinder.UrlSync

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Catalog.Product
  alias Edenflowers.Catalog.ProductCategory
  alias Edenflowers.Format
  alias Edenflowers.Translations
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    # Placing, editing or cancelling an order changes stock.
    if connected?(socket), do: EdenflowersWeb.Endpoint.subscribe("admin:orders")

    categories = Ash.read!(ProductCategory, actor: socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, ~t"Products")
     |> assign(:locale, Localize.get_locale())
     |> assign(:category_options, Enum.zip_with(Translations.translate(categories), categories, &{&1.name, &2.name}))}
  end

  @impl true
  def handle_params(params, uri, socket) do
    {:noreply, Cinder.UrlSync.handle_params(params, uri, socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={~t"Products"}>
          <:actions>
            <.button navigate={~p"/admin/products/new"} variant="primary" size="sm">
              <.icon name="hero-plus" class="h-4 w-4" />
              {~t"New product"}
            </.button>
          </:actions>
        </.admin_page_header>

        <Cinder.collection
          id="products-table"
          resource={Product}
          actor={@current_user}
          query_opts={[load: [:cheapest_price, :product_category, :product_variants]]}
          search={[
            label: ~t"Product",
            placeholder: ~t"Search name…",
            fn: &search_products/3
          ]}
          url_state={@url_state}
          sort_mode="exclusive"
          page_size={[default: 25, options: [10, 25, 50, 100]]}
          theme={EdenflowersWeb.Admin.CinderTheme}
          click={fn product -> JS.navigate(~p"/admin/products/#{product.id}") end}
        >
          <:col :let={product} field="name" search sort={[cycle: [:asc, :desc]]} label={~t"Name"}>
            <.link
              navigate={~p"/admin/products/#{product.id}"}
              class="max-w-28 inline-block truncate align-middle font-medium hover:underline sm:max-w-none"
            >
              {Translations.translate(product).name}
            </.link>
          </:col>
          <:col
            :let={product}
            field="product_category.name"
            sort
            filter={[type: :select, label: ~t"Category", prompt: ~t"All", options: @category_options]}
            label={~t"Category"}
            class="max-sm:hidden"
          >
            {Translations.translate(product.product_category).name}
          </:col>
          <:col :let={product} field="cheapest_price" sort label={~t"From"} class="text-right">
            <span :if={product.cheapest_price} class="whitespace-nowrap tabular-nums">
              {Format.currency(product.cheapest_price, @locale)}
            </span>
            <.badge :if={is_nil(product.cheapest_price)} tone={:warning}>{~t"No sizes"}</.badge>
          </:col>
          <:col :let={product} label={~t"Stock"} class="max-sm:hidden">
            <div :if={tracked_sizes(product) != []} class="flex flex-wrap gap-1">
              <.badge :for={size <- tracked_sizes(product)} tone={(size.stock_quantity == 0 && :warning) || :tag}>
                {stock_label(size)}
              </.badge>
            </div>
            <.blank :if={tracked_sizes(product) == []} />
          </:col>
          <:col
            :let={product}
            field="draft"
            sort
            filter={[
              type: :select,
              label: ~t"Status",
              prompt: ~t"All",
              options: [{~t"Draft", true}, {~t"Published", false}]
            ]}
            label={~t"Status"}
          >
            <.badge :if={product.draft} tone={:neutral}>{~t"Draft"}</.badge>
            <.badge :if={!product.draft} tone={:success}>{~t"Published"}</.badge>
          </:col>
          <:col :let={product} field="featured" sort label={~t"Favourite"} class="max-sm:hidden">
            <span :if={product.featured}>
              <.icon name="hero-star-solid" class="text-primary h-4 w-4" />
              <span class="sr-only">{~t"Favourite"}</span>
            </span>
            <.blank :if={!product.featured} />
          </:col>
          <:col :let={product} field="subscribable" sort label={~t"Subscription"} class="max-sm:hidden">
            <span :if={product.subscribable}>
              <.icon name="hero-arrow-path" class="text-primary h-4 w-4" />
              <span class="sr-only">{~t"Can be bought as a subscription"}</span>
            </span>
            <.blank :if={!product.subscribable} />
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "admin:orders"}, socket),
    do: {:noreply, Cinder.refresh_table(socket, "products-table")}

  defp tracked_sizes(product), do: Enum.reject(product.product_variants, &is_nil(&1.stock_quantity))

  defp stock_label(%{size: nil, stock_quantity: 0}), do: ~t"Sold out"
  defp stock_label(%{size: nil, stock_quantity: count}), do: ~t"#{count} left"
  defp stock_label(%{size: size, stock_quantity: 0}), do: ~t"#{variant_size_label(size)}: sold out"
  defp stock_label(%{size: size, stock_quantity: count}), do: ~t"#{variant_size_label(size)}: #{count} left"

  defp search_products(query, _searchable_columns, search_term) do
    require Ash.Query
    import Ash.Expr

    case_insensitive_term = Ash.CiString.new(search_term)

    Ash.Query.filter(
      query,
      expr(
        contains(name, ^case_insensitive_term) or
          contains(translations[:"sv-FI"][:name], ^case_insensitive_term) or
          contains(translations[:fi][:name], ^case_insensitive_term)
      )
    )
  end
end
