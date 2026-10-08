defmodule EdenflowersWeb.Store.ProductLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Changes.KeepSubscriptionAlone
  alias Edenflowers.Orders.Subscription
  alias EdenflowersWeb.Checkout.Fields

  alias Edenflowers.Catalog
  alias Edenflowers.Fulfillment
  alias Edenflowers.Translations

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  def mount(%{"id" => id}, %{"order_id" => order_id}, socket) do
    {:ok, product} = Catalog.get_product_by_id(id, load: [:product_category, :product_variants, :tax_rate])
    product_variants = product.product_variants
    product_category = Translations.translate(product.product_category)
    product = Translations.translate(product)

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
     |> assign(selected_variant: selected_variant)
     |> assign(subscribe?: false, interval_weeks: "1")
     |> assign(free_dist_km: product.free_delivery && Fulfillment.free_dist_km())}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        replaces_cart?:
          KeepSubscriptionAlone.replaces?(assigns.order.line_items, assigns.product.id, assigns.subscribe?),
        cart_subscription?: Enum.any?(assigns.order.line_items, & &1.interval_weeks)
      )

    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <div class="grid gap-10 md:grid-cols-[minmax(0,480px)_1fr] md:items-start md:gap-16">
          <header class="order-first md:hidden">
            <.link
              navigate={~p"/store/#{@product.product_category.slug}"}
              class="eyebrow text-base-content/70 link-underline-hover mb-5 inline-block w-fit"
            >
              {@product_category.name}
            </.link>
            <h1 class="page-title mb-3">
              {@product.name}
            </h1>
            <p class="font-serif text-base-content text-2xl">
              {Edenflowers.Format.storefront_price(@selected_variant.price, Edenflowers.Format.locale())}
            </p>
          </header>

          <figure class="bg-cream aspect-[4/5] relative overflow-hidden">
            <.image
              data-testid="product-image"
              src={@selected_variant.image_slug}
              alt={"#{@product.name} #{String.capitalize(to_string(@selected_variant.size))}"}
              width={1000}
              height={1250}
              sizes="(min-width: 768px) 480px, 100vw"
              priority
              class="h-full w-full object-cover"
            />
            <figcaption :if={@product.featured} class="product-mark">
              <span class="eyebrow text-base-content text-[0.6875rem]">{~t"Favourite"}</span>
            </figcaption>
          </figure>

          <div class="flex flex-col gap-8 md:max-w-prose">
            <header class="hidden md:block">
              <.link
                navigate={~p"/store/#{@product.product_category.slug}"}
                class="eyebrow text-base-content/70 link-underline-hover mb-5 inline-block w-fit"
              >
                {@product_category.name}
              </.link>
              <h1 id="product-details-heading" data-testid="product-name" class="page-title mb-3">
                {@product.name}
              </h1>
              <p data-testid="product-price" class="font-serif text-base-content text-2xl">
                {Edenflowers.Format.storefront_price(@selected_variant.price, Edenflowers.Format.locale())}
              </p>
            </header>

            <p data-testid="product-description" class="text-base-content text-lg leading-relaxed">
              {@product.description}
            </p>

            <p :if={@free_dist_km} data-testid="product-free-delivery" class="text-base-content/80 flex items-center gap-2">
              <.icon name="hero-truck" class="h-5 w-5" />
              {~t"Free delivery within #{km = @free_dist_km} km"}
            </p>

            <p
              :if={@product.subscribable}
              data-testid="product-subscribable"
              class="text-base-content/80 flex items-center gap-2"
            >
              <.icon name="hero-arrow-path" class="h-5 w-5" />
              {~t"Also as a subscription"}
            </p>

            <.form
              id="product-form"
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
                    class="size-option"
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
                    <span class="size-option__price text-base-content font-serif ml-2 text-lg">
                      {Edenflowers.Format.storefront_price(variant.price, Edenflowers.Format.locale())}
                    </span>
                  </label>
                </div>
              </fieldset>

              <fieldset :if={@product.subscribable} class="flex flex-col gap-3">
                <legend class="eyebrow text-base-content/70 mb-1">{~t"How to buy"}</legend>
                <div class="flex flex-wrap gap-x-6 gap-y-2">
                  <label class="size-option" data-active={(not @subscribe? && "true") || nil}>
                    <input
                      type="radio"
                      name="subscribe"
                      value="false"
                      checked={not @subscribe?}
                      class="sr-only"
                      data-testid="buy-once-option"
                    />
                    <span class="size-option__label font-serif text-xl">{~t"Buy once"}</span>
                  </label>
                  <label class="size-option" data-active={(@subscribe? && "true") || nil}>
                    <input
                      type="radio"
                      name="subscribe"
                      value="true"
                      checked={@subscribe?}
                      class="sr-only"
                      data-testid="subscribe-option"
                    />
                    <span class="size-option__label font-serif text-xl">{~t"Subscription"}</span>
                  </label>
                </div>
              </fieldset>

              <fieldset
                :if={@product.subscribable and @subscribe?}
                class="flex flex-col gap-3"
                data-testid="interval-options"
              >
                <legend class="eyebrow text-base-content/70 mb-1">{~t"How often"}</legend>
                <div class="flex flex-wrap gap-x-6 gap-y-2">
                  <label
                    :for={weeks <- Subscription.intervals()}
                    class="size-option"
                    data-active={(to_string(weeks) == @interval_weeks && "true") || nil}
                  >
                    <input
                      type="radio"
                      name="interval_weeks"
                      value={weeks}
                      checked={to_string(weeks) == @interval_weeks}
                      class="sr-only"
                      data-testid={"interval-option-#{weeks}"}
                    />
                    <span class="size-option__label font-serif text-xl">{Fields.interval_label(weeks)}</span>
                  </label>
                </div>
                <p class="text-base-content/75 text-base">{~t"Delivered regularly, skip or cancel any time"}</p>
              </fieldset>

              <p :if={@replaces_cart?} class="text-base-content/75 text-base" data-testid="replaces-cart-note">
                {if @cart_subscription?,
                  do: ~t"Replaces the subscription in your cart",
                  else: ~t"Replaces the bouquet in your cart"}
              </p>
              <.button
                type="submit"
                variant="primary"
                size="lg"
                phx-click={JS.exec("phx-show", to: "#cart-drawer")}
                data-testid="add-to-cart-button"
                class="w-full"
              >
                {if @replaces_cart?, do: ~t"Update cart", else: ~t"Add to cart"}
              </.button>
            </.form>

            <p class="text-base-content/75 text-base">
              {~t"Have a question?"}
              <.link navigate={~p"/faq"} class="link-underline-hover whitespace-nowrap">
                {~t"See the FAQ"}
              </.link>
            </p>
          </div>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  def handle_event("change", %{"product_variant_id" => id} = params, socket) do
    variant = Enum.find(socket.assigns.product_variants, &(&1.id == id))

    {:noreply,
     assign(socket,
       selected_variant: variant,
       subscribe?: params["subscribe"] == "true",
       interval_weeks: params["interval_weeks"] || socket.assigns.interval_weeks
     )}
  end

  def handle_event("submit", _params, socket) do
    subscription = if socket.assigns.subscribe?, do: %{interval_weeks: socket.assigns.interval_weeks}, else: %{}

    case Orders.add_line_item(socket.assigns.order.id, socket.assigns.selected_variant.id, 1, subscription) do
      {:ok, _line_item} ->
        {:noreply, socket}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, add_error_message(error))}
    end
  end

  # The cart's rules say why in their own message, already translated.
  defp add_error_message(%Ash.Error.Invalid{errors: [%{message: message} | _]}) when is_binary(message), do: message
  defp add_error_message(_error), do: ~t"This couldn't be added to your cart."
end
