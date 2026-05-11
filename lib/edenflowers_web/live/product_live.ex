defmodule EdenflowersWeb.ProductLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Store.{Product, Order}

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  def mount(%{"id" => id}, %{"order_id" => order_id}, socket) do
    locale = current_locale_atom()
    {:ok, product} = Product.get_by_id(id, load: [:product_variants, :tax_rate])
    product_variants = product.product_variants
    product_category = product.product_category |> Ash.load!(:translations) |> AshTranslation.translate(locale)

    selected_variant =
      case length(product_variants) do
        1 ->
          List.first(product_variants)

        2 ->
          List.first(product_variants)

        _ ->
          middle_index =
            product_variants
            |> length()
            |> div(2)

          Enum.at(product_variants, middle_index)
      end

    {:ok,
     socket
     |> assign(order_id: order_id)
     |> assign(product: product)
     |> assign(product_category: product_category)
     |> assign(product_variants: product_variants)
     |> assign(selected_variant: selected_variant)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <%!-- Magazine spread: photograph left, buy column right (with the
             description living inside it between price and size). On mobile
             the grid collapses to image-first, then the buy column. --%>
        <div class="grid gap-10 md:grid-cols-[minmax(0,480px)_1fr] md:items-start md:gap-16">
          <%!-- Photograph: capped at 480px wide on desktop so it sits at
               a calmer scale; aspect 4:5 matches the mobile grid card. --%>
          <figure class="bg-cream aspect-[4/5] relative overflow-hidden">
            <img
              data-testid="product-image"
              src={
                @selected_variant.image_slug |> Imgproxy.new() |> Imgproxy.resize(1000, 1250, type: "fill") |> to_string()
              }
              alt={"#{@product.name} #{String.capitalize(to_string(@selected_variant.size))}"}
              class="h-full w-full object-cover"
              loading="eager"
            />
            <figcaption :if={@product.featured} class="product-mark">
              <span class="product-mark__eyebrow">{~t"Favourite"}</span>
            </figcaption>
          </figure>

          <div class="flex flex-col gap-8 md:max-w-prose">
            <header>
              <.link
                navigate={~p"/store/#{@product.product_category.slug}"}
                class="eyebrow text-base-content/70 link-underline-hover-nav mb-5 inline-block w-fit"
              >
                {@product_category.name}
              </.link>
              <h1 id="product-details-heading" data-testid="product-name" class="page-title mb-3">
                {@product.name}
              </h1>
              <p data-testid="product-price" class="font-serif text-base-content text-2xl">
                {Edenflowers.Utils.format_money(@selected_variant.price)}
              </p>
            </header>

            <p data-testid="product-description" class="text-base-content text-lg leading-relaxed">
              {@product.description}
            </p>

            <.form
              for={%{}}
              phx-submit="submit"
              phx-change="change"
              class="flex flex-col gap-6"
              data-testid="product-form"
            >
              <fieldset class="flex flex-col gap-3">
                <legend class="eyebrow text-base-content/70 mb-1">{~t"Size"}</legend>
                <input type="hidden" name="product_variant_id" value="" />
                <div class="flex flex-wrap gap-x-6 gap-y-2">
                  <label
                    :for={variant <- @product_variants}
                    class="size-option group cursor-pointer"
                    data-active={(@selected_variant.id == variant.id && "true") || nil}
                  >
                    <input
                      type="radio"
                      name="product_variant_id"
                      value={variant.id}
                      checked={@selected_variant.id == variant.id}
                      class="sr-only"
                      data-testid={"variant-option-#{variant.size}"}
                    />
                    <span class="size-option__label font-serif text-xl">
                      {String.capitalize(to_string(variant.size))}
                    </span>
                    <span class="size-option__price text-base-content/75 ml-2 text-sm">
                      {Edenflowers.Utils.format_money(variant.price)}
                    </span>
                  </label>
                </div>
              </fieldset>

              <.button
                type="submit"
                variant="primary"
                size="lg"
                phx-click={JS.push_focus() |> JS.exec("phx-show", to: "#cart-drawer")}
                data-testid="add-to-cart-button"
                class="w-full"
              >
                {~t"Add to cart"}
              </.button>
            </.form>

            <p class="text-base-content/75 text-base">
              {~t"Have a question?"}
              <.link navigate={~p"/faq"} class="text-base-content link-underline-hover-nav whitespace-nowrap">
                {~t"See our FAQ"}
              </.link>
            </p>
          </div>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  defp current_locale_atom, do: Localize.get_locale().cldr_locale_id

  def handle_event("change", %{"product_variant_id" => id}, socket) do
    variant = Enum.find(socket.assigns.product_variants, &(&1.id == id))
    {:noreply, assign(socket, selected_variant: variant)}
  end

  def handle_event("submit", _params, socket) do
    Order.add_line_item(socket.assigns.order, socket.assigns.selected_variant.id, 1)

    {:noreply, socket}
  end
end
