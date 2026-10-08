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
          <:col :let={product} field="cheapest_price" sort label={~t"From"} class="text-right">
            <span :if={product.cheapest_price} class="whitespace-nowrap tabular-nums">
              {Format.currency(product.cheapest_price, @locale)}
            </span>
            <.badge :if={is_nil(product.cheapest_price)} tone={:warning}>{~t"No sizes"}</.badge>
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
          <:col :let={product} field="featured" sort label={~t"Featured"} class="max-sm:hidden">
            <span :if={product.featured}>
              <.icon name="hero-star-solid" class="text-primary h-4 w-4" />
              <span class="sr-only">{~t"Featured on the home page"}</span>
            </span>
          </:col>
          <:col :let={product} field="subscribable" sort label={~t"Subscription"} class="max-sm:hidden">
            <span :if={product.subscribable}>
              <.icon name="hero-arrow-path" class="text-primary h-4 w-4" />
              <span class="sr-only">{~t"Can be bought as a subscription"}</span>
            </span>
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end
end
