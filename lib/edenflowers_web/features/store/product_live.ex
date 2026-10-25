defmodule EdenflowersWeb.Store.ProductLive do
  @moduledoc """
  Public product page for choosing a size and adding it to the cart or starting a subscription.
  """

  use EdenflowersWeb, :live_view

  alias Edenflowers.Orders
  alias Edenflowers.Orders.LineItem.Changes.KeepSubscriptionAlone
  alias Edenflowers.Orders.Subscription
  alias EdenflowersWeb.Checkout.Fields

  alias Edenflowers.Catalog
  alias Edenflowers.Catalog.ProductType
  alias Edenflowers.Fulfillment
  alias Edenflowers.Translations

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(%{"id" => id}, %{"order_id" => order_id}, socket) do
    product = get_product!(id)

    if connected?(socket),
      do: Phoenix.PubSub.subscribe(Edenflowers.PubSub, "product_variant:changed:#{product.id}")

    product_variants = product.product_variants
    product_category = Translations.translate(product.product_category)
    product = Translations.translate(product)

    cart_line = cart_line(socket.assigns.order, product.id)

    selected_variant =
      (cart_line && Enum.find(product_variants, &(&1.id == cart_line.product_variant_id))) ||
        default_variant(selectable_variants(product_variants))

    {:ok,
     socket
     |> assign(order_id: order_id)
     |> assign(product: product)
     |> assign(gallery: product.photo_slugs -- product.hidden_photo_slugs)
     |> assign(
       page_title: product.name,
       alternates: alternates("/#{language}/product/#{product.id}"),
       page_description: product.description,
       og_image: image_url(product.main_photo_slug, 1200, 630),
       json_ld: json_ld(product, product_variants)
     )
     |> assign(product_category: product_category)
     |> assign(product_variants: product_variants)
     |> assign(selected_variant: selected_variant)
     |> assign(photo_slug: selected_variant.photo_slug)
     |> assign(subscribe?: if(cart_line, do: cart_line.interval_weeks != nil, else: false))
     |> assign(interval_weeks: to_string((cart_line && cart_line.interval_weeks) || 1))
     |> assign(has_subscription?: has_subscription?(socket.assigns.current_user))
     |> assign(free_dist_km: product.free_delivery && Fulfillment.free_dist_km())}
  end

  @impl true
  def render(assigns) do
    %{order: order, product: product, subscribe?: subscribe?} = assigns
    lines = Enum.reject(order.line_items, & &1.is_card)
    replaces_cart? = KeepSubscriptionAlone.replaces?(order.line_items, product.id, subscribe?)

    assigns =
      assign(assigns,
        in_cart?: in_cart?(assigns),
        replaces_cart?: replaces_cart?,
        cart_note: replaces_cart? && replace_note(lines),
        blocked?: lines != [] and not replaces_cart? and (subscribe? or Enum.any?(lines, & &1.interval_weeks))
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
        <div class="grid gap-10 md:grid-cols-[minmax(0,480px)_1fr] md:grid-rows-[auto_1fr] md:items-start md:gap-x-16 md:gap-y-8">
          <header class="md:col-start-2 md:row-start-1 md:max-w-prose">
            <.link
              navigate={~q"/#{language}/store/#{@product_category.slug}"}
              class="eyebrow text-base-content/70 link-underline-hover touch-target mb-5 inline-block w-fit"
            >
              {@product_category.name}
            </.link>
            <h1 id="product-details-heading" data-testid="product-name" class="page-title mb-3">
              {@product.name}
            </h1>
            <p data-testid="product-price" class="font-serif text-base-content text-2xl">
              {Edenflowers.Format.storefront_price(@selected_variant.price, Edenflowers.Format.locale())}
              <span :if={@subscribe?} class="text-base-content/70 text-lg" data-testid="per-delivery">
                {~t"per delivery"}
              </span>
            </p>
          </header>

          <div class="md:col-start-1 md:row-span-2 md:row-start-1">
            <figure class="bg-cream aspect-[4/5] relative overflow-hidden">
              <.image
                data-testid="product-image"
                src={@photo_slug}
                alt={"#{@product.name} #{variant_size_label(@selected_variant.size)}"}
                width={1000}
                height={1250}
                sizes="(min-width: 768px) 480px, 100vw"
                priority
                class="h-full w-full object-cover"
              />
            </figure>
            <%!-- Eight columns whatever the count, so eight photos still fit one row on a phone. --%>
            <ul
              :if={length(@gallery) > 1}
              aria-label={~t"Photos"}
              class="mt-2 grid grid-cols-8 gap-2"
              data-testid="product-photos"
            >
              <li :for={{slug, index} <- Enum.with_index(@gallery, 1)}>
                <button
                  type="button"
                  phx-click="show_photo"
                  phx-value-slug={slug}
                  aria-pressed={to_string(slug == @photo_slug)}
                  class={["bg-cream aspect-[4/5] outline-primary relative block w-full overflow-hidden outline-offset-2 focus-visible:outline-2", slug == @photo_slug && "outline-base-content outline-1", slug != @photo_slug && "opacity-70 hover:opacity-100"]}
                >
                  <span class="sr-only">{~t"Photo #{index}"}</span>
                  <.image src={slug} alt="" width={120} height={150} class="absolute inset-0 h-full w-full object-cover" />
                </button>
              </li>
            </ul>
          </div>

          <div class="flex flex-col gap-8 md:col-start-2 md:row-start-2 md:max-w-prose">
            <p data-testid="product-description" class="text-base-content text-lg leading-relaxed">
              {@product.description}
            </p>

            <p
              :if={@free_dist_km}
              data-testid="product-free-delivery"
              class="text-base-content/80 flex items-center gap-2"
            >
              <.icon name="hero-truck" class="h-5 w-5" />
              {~t"Free delivery within #{km = @free_dist_km} km"}
            </p>

            <.form
              id="product-form"
              for={%{}}
              phx-submit="submit"
              phx-change="change"
              class="flex flex-col gap-6"
              data-testid="product-form"
            >
              <fieldset :if={not one_size?(@product_variants)} class="flex flex-col gap-3">
                <legend class="eyebrow text-base-content/70 mb-1">{~t"Size"}</legend>
                <input type="hidden" name="product_variant_id" value="" />
                <div class="flex flex-wrap gap-x-6 gap-y-2">
                  <label
                    :for={variant <- @product_variants}
                    class="size-option touch-target"
                    data-active={(@selected_variant.id == variant.id && "true") || nil}
                  >
                    <input
                      type="radio"
                      name="product_variant_id"
                      value={variant.id}
                      checked={@selected_variant.id == variant.id}
                      disabled={sold_out?(variant)}
                      class="sr-only"
                      data-testid={"variant-option-#{variant.size}"}
                    />
                    <span class="size-option__label font-serif text-xl">
                      {variant_size_label(variant.size)}
                    </span>
                    <span class="size-option__price text-base-content font-serif ml-2 text-lg">
                      <%= if sold_out?(variant) do %>
                        {~t"Sold out"}
                      <% else %>
                        {Edenflowers.Format.storefront_price(variant.price, Edenflowers.Format.locale())}
                      <% end %>
                    </span>
                  </label>
                </div>
              </fieldset>

              <p
                :if={details(@product_category, @selected_variant)}
                class="text-base-content/80 font-serif -mt-4 text-lg italic"
                data-testid="variant-dimensions"
              >
                {details(@product_category, @selected_variant)}
              </p>

              <fieldset :if={@product.subscribable} class="flex flex-col gap-3">
                <legend class="eyebrow text-base-content/70 mb-1">{~t"How to buy"}</legend>
                <div class="flex flex-wrap gap-x-6 gap-y-2">
                  <label class="size-option touch-target" data-active={(not @subscribe? && "true") || nil}>
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
                  <label class="size-option touch-target" data-active={(@subscribe? && "true") || nil}>
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
                    class="size-option touch-target"
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
                <div class="text-base-content/75 flex flex-col gap-1 text-base" data-testid="subscription-explainer">
                  <p>{~t"Pause or cancel anytime."}</p>
                  <p :if={@has_subscription?} data-testid="already-subscribed">
                    {~t"You already have a subscription."}
                    <.link navigate={~p"/account"} class="link-underline-hover text-base-content">
                      {~t"Manage it from your account."}
                    </.link>
                  </p>
                </div>
              </fieldset>

              <%= cond do %>
                <% @in_cart? -> %>
                  <.button
                    type="button"
                    variant="primary"
                    size="lg"
                    phx-click={JS.exec("phx-show", to: "#cart-drawer")}
                    data-testid="add-to-cart-button"
                    class="w-full"
                  >
                    {~t"Show cart"}
                  </.button>
                <% @blocked? -> %>
                  <p class="text-base-content/75 text-base" data-testid="blocked-note">
                    {~t"A subscription is checked out on its own. Empty your cart to add this."}
                  </p>
                  <.button
                    type="button"
                    variant="secondary"
                    size="lg"
                    phx-click={JS.exec("phx-show", to: "#cart-drawer")}
                    data-testid="add-to-cart-button"
                    class="w-full"
                  >
                    {~t"View cart"}
                  </.button>
                <% true -> %>
                  <p :if={@cart_note} class="text-base-content/75 text-base" data-testid="replaces-cart-note">
                    {@cart_note}
                  </p>
                  <.button
                    :if={sold_out?(@selected_variant)}
                    type="button"
                    variant="primary"
                    size="lg"
                    disabled
                    data-testid="add-to-cart-button"
                    class="w-full"
                  >
                    {~t"Sold out"}
                  </.button>
                  <.button
                    :if={not sold_out?(@selected_variant)}
                    type="submit"
                    variant="primary"
                    size="lg"
                    data-testid="add-to-cart-button"
                    class="w-full"
                  >
                    {if @replaces_cart?, do: ~t"Update cart", else: ~t"Add to cart"}
                  </.button>
              <% end %>
            </.form>

            <p class="text-base-content/75 text-base">
              {~t"Have a question?"}
              <.link navigate={~q"/#{language}/faq"} class="link-underline-hover whitespace-nowrap">
                {~t"See the FAQ"}
              </.link>
            </p>
          </div>
        </div>

        <section
          :if={@product.subscribable}
          aria-labelledby="subscription-faq-heading"
          class="mt-20 max-w-3xl md:mt-28"
          data-testid="subscription-faq"
        >
          <h2 id="subscription-faq-heading" class="section-title mb-6">{~t"How subscriptions work"}</h2>
          <details
            :for={{question, answer} <- EdenflowersWeb.Marketing.FaqLive.subscription_questions()}
            class="collapse-arrow border-base-content/12 collapse rounded-none border-b has-[summary:focus-visible]:outline-primary has-[summary:focus-visible]:outline-2 has-[summary:focus-visible]:outline-offset-2 first-of-type:border-t"
          >
            <summary class="collapse-title font-serif text-balance pr-10 pl-0 text-xl leading-snug">
              {question}
            </summary>
            <div class="collapse-content text-base-content/80 text-[1.0625rem] px-0 leading-relaxed">
              <p class="max-w-[60ch]">{answer}</p>
            </div>
          </details>
        </section>
      </.container>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("change", %{"product_variant_id" => id} = params, socket) do
    variant = Enum.find(socket.assigns.product_variants, &(&1.id == id))
    # Toggling a subscription also sends the size, which mustn't undo a thumbnail pick.
    photo_slug =
      if variant.id == socket.assigns.selected_variant.id, do: socket.assigns.photo_slug, else: variant.photo_slug

    {:noreply,
     assign(socket,
       selected_variant: variant,
       photo_slug: photo_slug,
       subscribe?: params["subscribe"] == "true",
       interval_weeks: params["interval_weeks"] || socket.assigns.interval_weeks
     )}
  end

  def handle_event("show_photo", %{"slug" => slug}, socket) do
    if slug in socket.assigns.gallery,
      do: {:noreply, assign(socket, photo_slug: slug)},
      else: {:noreply, socket}
  end

  def handle_event("submit", _params, socket) do
    subscription = if socket.assigns.subscribe?, do: %{interval_weeks: socket.assigns.interval_weeks}, else: %{}

    case Orders.add_line_item(socket.assigns.order.id, socket.assigns.selected_variant.id, 1, subscription) do
      {:ok, _line_item} ->
        {:noreply, push_event(socket, "js-exec", %{to: "#cart-drawer", attr: "phx-show"})}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, add_error_message(error))}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "product_variant:changed:" <> _}, socket) do
    {:ok, product} = Catalog.get_product_by_id(socket.assigns.product.id)
    variants = product.product_variants

    selected_variant =
      Enum.find(variants, &(&1.id == socket.assigns.selected_variant.id)) ||
        default_variant(selectable_variants(variants))

    {:noreply, assign(socket, product_variants: variants, selected_variant: selected_variant)}
  end

  defp get_product!(id) do
    case Catalog.get_product_by_id(id) do
      {:ok, product} -> product
      # A malformed id is an invalid-filter error rather than NotFound; both should 404.
      {:error, _} -> raise Ash.Error.Query.NotFound, resource: Edenflowers.Catalog.Product
    end
  end

  defp sold_out?(variant), do: variant.stock_quantity == 0

  defp details(category, variant), do: ProductType.describe(category.product_type, variant)

  # Sold-out sizes can't be picked, unless every size is sold out.
  defp selectable_variants(variants) do
    case Enum.reject(variants, &sold_out?/1) do
      [] -> variants
      in_stock -> in_stock
    end
  end

  defp default_variant([first, _second]), do: first
  defp default_variant(variants), do: Enum.at(variants, div(length(variants), 2))

  defp json_ld(product, variants) do
    availability =
      if Enum.all?(variants, &sold_out?/1), do: "https://schema.org/OutOfStock", else: "https://schema.org/InStock"

    offers =
      case variants do
        [variant] ->
          %{"@type" => "Offer", "price" => Decimal.to_string(variant.price, :normal)}

        _ ->
          prices = Enum.map(variants, & &1.price)

          %{
            "@type" => "AggregateOffer",
            "lowPrice" => prices |> Enum.min(Decimal) |> Decimal.to_string(:normal),
            "highPrice" => prices |> Enum.max(Decimal) |> Decimal.to_string(:normal),
            "offerCount" => length(variants)
          }
      end

    %{
      "@context" => "https://schema.org",
      "@type" => "Product",
      "name" => product.name,
      "description" => product.description,
      "image" => image_url(product.main_photo_slug, 1200, 1200),
      "offers" => Map.merge(offers, %{"priceCurrency" => "EUR", "availability" => availability})
    }
  end

  # A single size-less variant has nothing to choose; the header shows its price.
  defp one_size?([%{size: nil}]), do: true
  defp one_size?(_variants), do: false

  defp cart_line(order, product_id), do: Enum.find(order.line_items, &(not &1.is_card and &1.product_id == product_id))

  defp in_cart?(%{order: order, product: product, selected_variant: variant} = assigns) do
    interval = if assigns.subscribe?, do: String.to_integer(assigns.interval_weeks)

    case Enum.reject(order.line_items, & &1.is_card) do
      [%{product_id: product_id, product_variant_id: variant_id, quantity: 1, interval_weeks: ^interval}] ->
        product_id == product.id and variant_id == variant.id

      _ ->
        false
    end
  end

  # Swapping a single bouquet is plain from the "Update cart" button; replacing
  # several is spelled out so nothing goes silently.
  defp replace_note([%{quantity: 1}]), do: nil

  defp replace_note(lines) do
    count = Enum.sum_by(lines, & &1.quantity)
    amount = Enum.reduce(lines, Decimal.new(0), &Decimal.add(&2, &1.subtotal))

    ~t"Replaces the #{count = count} bouquets (#{amount = Edenflowers.Format.currency(amount, Edenflowers.Format.locale())}) in your cart."
  end

  defp has_subscription?(nil), do: false

  defp has_subscription?(user) do
    Orders.list_my_subscriptions!(actor: user)
    |> Enum.any?(&(&1.state != :cancelled))
  end

  # The cart's rules say why in their own message, already translated.
  defp add_error_message(%Ash.Error.Invalid{errors: [%{message: message} | _]}) when is_binary(message), do: message
  defp add_error_message(_error), do: ~t"This couldn't be added to your cart."
end
