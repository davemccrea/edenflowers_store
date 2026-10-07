defmodule EdenflowersWeb.Admin.ProductsLive do
  use EdenflowersWeb, :live_view
  use Cinder.UrlSync

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Catalog.Product
  alias Edenflowers.Catalog.ProductCategory
  alias Edenflowers.Format

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    categories = Ash.read!(ProductCategory, actor: socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, ~t"Products")
     |> assign(:locale, Localize.get_locale())
     |> assign(:category_options, Enum.map(categories, &{&1.name, &1.name}))}
  end

  @impl true
  def handle_params(params, uri, socket) do
    {:noreply, Cinder.UrlSync.handle_params(params, uri, socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="full">
        <.admin_page_header title={~t"Products"}>
          <:actions>
            <.button navigate={~p"/admin/products/new"} variant="neutral" size="sm">
              <.icon name="hero-plus" class="h-4 w-4" />
              {~t"New product"}
            </.button>
          </:actions>
        </.admin_page_header>

        <Cinder.collection
          id="products-table"
          resource={Product}
          actor={@current_user}
          query_opts={[load: [:cheapest_price, :product_category]]}
          url_state={@url_state}
          show_filters={:toggle}
          sort_mode="exclusive"
          page_size={[default: 25, options: [10, 25, 50, 100]]}
          theme={EdenflowersWeb.Admin.CinderTheme}
          click={fn product -> JS.navigate(~p"/admin/products/#{product.id}") end}
        >
          <:col :let={product} field="name" search sort={[cycle: [:asc, :desc]]} label={~t"Name"}>
            <.link navigate={~p"/admin/products/#{product.id}"} class="font-medium hover:underline">
              {product.name}
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
            {product.product_category.name}
          </:col>
          <:col :let={product} field="cheapest_price" sort label={~t"From"}>
            <span :if={product.cheapest_price} class="whitespace-nowrap tabular-nums">
              {Format.currency(product.cheapest_price, @locale)}
            </span>
            <span :if={is_nil(product.cheapest_price)} class="badge badge-sm admin-badge-warning font-medium">
              {~t"No sizes"}
            </span>
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
            <span :if={product.draft} class="badge badge-sm admin-badge-neutral font-medium">{~t"Draft"}</span>
            <span :if={!product.draft} class="badge badge-sm admin-badge-success font-medium">
              {~t"Published"}
            </span>
          </:col>
          <:col :let={product} field="featured" sort label={~t"Featured"} class="max-sm:hidden">
            <.icon :if={product.featured} name="hero-star-solid" class="text-primary h-4 w-4" />
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end
end
