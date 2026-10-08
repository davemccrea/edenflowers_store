defmodule EdenflowersWeb.Store.ProductLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Changes.KeepSubscriptionAlone
  alias Edenflowers.Orders.Subscription
  alias EdenflowersWeb.Admin.Components, as: AdminComponents
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

    cart_line = cart_line(socket.assigns.order, product.id)

    default_variant =
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

    selected_variant =
      (cart_line && Enum.find(product_variants, &(&1.id == cart_line.product_variant_id))) || default_variant

    {:ok,
     socket
     |> assign(order_id: order_id)
     |> assign(product: product)
     |> assign(product_category: product_category)
     |> assign(product_variants: product_variants)
     |> assign(selected_variant: selected_variant)
     |> assign(subscribe?: if(cart_line, do: cart_line.interval_weeks != nil, else: product.subscribable))
     |> assign(interval_weeks: to_string((cart_line && cart_line.interval_weeks) || 1))
     |> assign(has_subscription?: has_subscription?(socket.assigns.current_user))
     |> assign(free_dist_km: product.free_delivery && Fulfillment.free_dist_km())}
  end

  def render(assigns) do
    %{order: order, product: product, subscribe?: subscribe?} = assigns
    lines = Enum.reject(order.line_items, & &1.is_card)
    replaces_cart? = KeepSubscriptionAlone.replaces?(order.line_items, product.id, subscribe?)

    assigns =
      assign(assigns,
        in_cart?: in_cart?(assigns),
        replaces_cart?: replaces_cart?,
        cart_note: replaces_cart? && replace_note(lines, assigns),
        blocked?: lines != [] and not replaces_cart? and (subscribe? or Enum.any?(lines, & &1.interval_weeks))
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
              <span :if={@subscribe?} class="text-base-content/70 text-lg">{~t"per delivery"}</span>
            </p>
          </header>

          <figure class="bg-cream aspect-[4/5] relative overflow-hidden">
            <.image
              data-testid="product-image"
              src={@selected_variant.image_slug}
              alt={"#{@product.name} #{AdminComponents.variant_size_label(@selected_variant.size)}"}
              width={1000}
              height={1250}
              sizes="(min-width: 768px) 480px, 100vw"
              priority
              class="h-full w-full object-cover"
            />
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
                <span :if={@subscribe?} class="text-base-content/70 text-lg" data-testid="per-delivery">
                  {~t"per delivery"}
                </span>
              </p>
            </header>

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
                      {AdminComponents.variant_size_label(variant.size)}
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
                <div class="text-base-content/75 flex flex-col gap-1 text-base" data-testid="subscription-explainer">
                  <p>
                    {~t"Your card is charged #{days = Subscription.lead_days()} days before each one. Pause or cancel from your account."}
                  </p>
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
                  <p class="text-base-content/75 text-base" data-testid="in-cart-note">{~t"This is in your cart."}</p>
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
                  <.button type="submit" variant="primary" size="lg" data-testid="add-to-cart-button" class="w-full">
                    {if @replaces_cart?, do: ~t"Update cart", else: ~t"Add to cart"}
                  </.button>
              <% end %>
            </.form>

            <p class="text-base-content/75 text-base">
              {~t"Have a question?"}
              <.link navigate={~p"/faq"} class="link-underline-hover whitespace-nowrap">
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
            class="collapse-arrow border-base-content/12 collapse rounded-none border-b first-of-type:border-t"
          >
            <summary class="collapse-title font-serif text-balance px-0 text-xl leading-snug">{question}</summary>
            <div class="collapse-content text-base-content/80 text-[1.0625rem] px-0 leading-relaxed">
              <p class="max-w-[60ch]">{answer}</p>
            </div>
          </details>
        </section>
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
        {:noreply, push_event(socket, "js-exec", %{to: "#cart-drawer", attr: "phx-show"})}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, add_error_message(error))}
    end
  end

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

  # Says what the add takes out of the cart, so nothing goes silently.
  defp replace_note([%{quantity: 1} = line], assigns) do
    ~t"Changes your cart from #{from = line_label(line.variant_size, line.interval_weeks)} to #{to = line_label(assigns.selected_variant.size, assigns.subscribe? && String.to_integer(assigns.interval_weeks))}."
  end

  defp replace_note(lines, _assigns) do
    count = Enum.sum_by(lines, & &1.quantity)
    amount = Enum.reduce(lines, Decimal.new(0), &Decimal.add(&2, &1.subtotal))

    ~t"Replaces the #{count = count} bouquets (#{amount = Edenflowers.Format.currency(amount, Edenflowers.Format.locale())}) in your cart."
  end

  defp line_label(size, nil), do: ~t"#{size = AdminComponents.variant_size_label(size)}, bought once"
  defp line_label(size, false), do: line_label(size, nil)

  defp line_label(size, weeks),
    do: "#{AdminComponents.variant_size_label(size)}, #{String.downcase(Fields.interval_label(weeks))}"

  defp has_subscription?(nil), do: false

  defp has_subscription?(user) do
    Orders.list_my_subscriptions!(actor: user)
    |> Enum.any?(&(&1.state != :cancelled))
  end

  # The cart's rules say why in their own message, already translated.
  defp add_error_message(%Ash.Error.Invalid{errors: [%{message: message} | _]}) when is_binary(message), do: message
  defp add_error_message(_error), do: ~t"This couldn't be added to your cart."
end
