defmodule EdenflowersWeb.ProductLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Store.{Product, LineItem}

  def mount(%{"id" => id}, %{"order_id" => order_id}, socket) do
    {:ok, product} = Product.get_by_id(id, load: [:product_variants, :tax_rate])
    variants = product.product_variants

    selected_variant =
      case length(variants) do
        1 ->
          List.first(variants)

        2 ->
          List.first(variants)

        _ ->
          middle_index =
            variants
            |> length()
            |> div(2)

          Enum.at(variants, middle_index)
      end

    {:ok,
     socket
     |> assign(order_id: order_id)
     |> assign(product: product)
     |> assign(variants: variants)
     |> assign(selected_variant: selected_variant)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app order={@order} flash={@flash}>
      <div class="container my-36">
        <%!-- Breadcrumbs --%>
        <nav aria-label="Breadcrumb" class="mb-8 text-sm">
          <ol class="flex items-center gap-2">
            <li>
              <.link navigate={~p"/"} class="text-base-content/60 hover:text-base-content">
                {gettext("Home")}
              </.link>
            </li>
            <li class="text-base-content/40">
              <.icon name="hero-chevron-right" class="h-4 w-4" />
            </li>
            <li>
              <.link navigate={~p"/#store"} class="text-base-content/60 hover:text-base-content">
                {gettext("Store")}
              </.link>
            </li>
            <li class="text-base-content/40">
              <.icon name="hero-chevron-right" class="h-4 w-4" />
            </li>
            <li aria-current="page" class="text-base-content font-medium">
              {@product.name}
            </li>
          </ol>
        </nav>

        <div class="grid gap-12 md:grid-cols-2">
          <%!-- Product Image --%>
          <figure class="relative overflow-hidden rounded shadow-md">
            <img
              src={@selected_variant.image_slug}
              alt={"#{@product.name} - #{String.capitalize(to_string(@selected_variant.size))} size"}
              class="aspect-square w-full object-cover"
            />
            <div class="badge badge-primary badge-outline absolute top-4 right-4">{gettext("Popular")}</div>
            <%!-- Optionally add figcaption here if needed --%>
          </figure>

          <%!-- Product Details --%>
          <section aria-labelledby="product-details-heading" class="flex flex-col gap-8">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3">
                <h1 id="product-details-heading" class="font-serif text-4xl tracking-wide">{@product.name}</h1>
              </div>
              <p class="text-2xl">
                {Edenflowers.Utils.format_money(@selected_variant.price)}
              </p>
            </div>

            <div class="text-base-content/80 prose max-w-none">
              <p class="leading-relaxed">{@product.description}</p>
            </div>

            <div class="flex flex-col gap-6">
              <%!-- Size Selection --%>
              <.form for={%{}} phx-submit="add_to_cart" phx-change="select_variant" class="flex flex-col gap-4">
                <fieldset>
                  <legend class="mb-1 text-base font-medium">{gettext("Select Size")}</legend>
                  <div class="flex flex-col flex-wrap gap-2 md:flex-row">
                    <label
                      :for={variant <- @variants}
                      class={["border-base-300 flex flex-1 cursor-pointer items-center gap-3 rounded border px-4 py-3 transition-all hover:border-primary", @selected_variant.id == variant.id && "border-primary bg-primary/5"]}
                    >
                      <input
                        type="radio"
                        name="variant_id"
                        value={variant.id}
                        checked={@selected_variant.id == variant.id}
                        class="radio radio-sm radio-primary"
                      />
                      <div class="flex flex-col">
                        <span class="font-medium">{String.capitalize(to_string(variant.size))}</span>
                        <span class="text-base-content/60 text-sm">
                          {Edenflowers.Utils.format_money(variant.price)}
                        </span>
                      </div>
                    </label>
                  </div>
                </fieldset>

                <button type="submit" class="btn btn-primary btn-lg">
                  <span class="flex items-center gap-2">
                    <.icon name="hero-shopping-bag" class="h-5 w-5" />
                    {gettext("Add to Cart")}
                  </span>
                </button>
              </.form>
            </div>
          </section>
        </div>

        <%!-- Visual Divider --%>
        <div class="my-24 flex items-center justify-center" role="separator">
          <div class="bg-base-300 h-px w-full max-w-3xl"></div>
          <div class="text-base-content/40 mx-4">
            <.icon name="hero-sparkles" class="h-6 w-6" />
          </div>
          <div class="bg-base-300 h-px w-full max-w-3xl"></div>
        </div>

        <%!-- FAQs Section --%>
        <section aria-labelledby="faq-heading" class="m-auto max-w-4xl">
          <h2 id="faq-heading" class="font-serif mb-12 text-center text-3xl">{gettext("Frequently Asked Questions")}</h2>

          <div class="space-y-4">
            <div class="collapse collapse-arrow bg-base-100 border-base-300 rounded-lg border">
              <input type="radio" name="my-accordion-2" checked="checked" />
              <div class="collapse-title font-medium">{gettext("How long will my flowers stay fresh?")}</div>
              <div class="collapse-content text-base-content/80">
                <p>
                  {gettext(
                    "Our flowers are carefully selected and arranged to last 5-7 days with proper care. We recommend changing the water every 2-3 days, trimming the stems, and keeping them away from direct sunlight and drafts."
                  )}
                </p>
              </div>
            </div>
            <div class="collapse collapse-arrow bg-base-100 border-base-300 rounded-lg border">
              <input type="radio" name="my-accordion-2" />
              <div class="collapse-title font-medium">{gettext("What is your delivery policy?")}</div>
              <div class="collapse-content text-base-content/80">
                <p>
                  {gettext(
                    "We offer same-day delivery for orders placed before 2 PM on weekdays. For weekend deliveries, please place your order by Friday 2 PM. All our deliveries are carefully handled to ensure your flowers arrive in perfect condition."
                  )}
                </p>
              </div>
            </div>
            <div class="collapse collapse-arrow bg-base-100 border-base-300 rounded-lg border">
              <input type="radio" name="my-accordion-2" />
              <div class="collapse-title font-medium">{gettext("Can I include a personal message with my order?")}</div>
              <div class="collapse-content text-base-content/80">
                <p>
                  {gettext(
                    "Yes! You can add a personal message during checkout. We'll include it on a beautiful card with your delivery. Messages can be up to 200 characters."
                  )}
                </p>
              </div>
            </div>
            <div class="collapse collapse-arrow bg-base-100 border-base-300 rounded-lg border">
              <input type="radio" name="my-accordion-2" />
              <div class="collapse-title font-medium">{gettext("Do you offer subscription services?")}</div>
              <div class="collapse-content text-base-content/80">
                <p>
                  {gettext(
                    "Yes, we offer weekly, bi-weekly, and monthly subscription services. You can customize your subscription to match your preferences and schedule. Subscribers receive a 10% discount on all orders."
                  )}
                </p>
              </div>
            </div>
            <div class="collapse collapse-arrow bg-base-100 border-base-300 rounded-lg border">
              <input type="radio" name="my-accordion-2" />
              <div class="collapse-title font-medium">{gettext("What happens if I'm not home for delivery?")}</div>
              <div class="collapse-content text-base-content/80">
                <p>
                  {gettext(
                    "Our delivery team will attempt to leave your flowers in a safe, shaded location. If no suitable location is available, they will leave a note with instructions for redelivery. You can also specify delivery instructions during checkout."
                  )}
                </p>
              </div>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  def handle_event("select_variant", %{"variant_id" => id}, socket) do
    variant = Enum.find(socket.assigns.variants, &(&1.id == id))
    {:noreply, assign(socket, selected_variant: variant)}
  end

  def handle_event("add_to_cart", _params, socket) do
    LineItem.add_item(%{
      order_id: socket.assigns.order_id,
      product_id: socket.assigns.product.id,
      product_variant_id: socket.assigns.selected_variant.id,
      product_name: socket.assigns.product.name,
      product_image_slug: socket.assigns.selected_variant.image_slug,
      quantity: 1,
      unit_price: socket.assigns.selected_variant.price,
      tax_rate: socket.assigns.product.tax_rate.percentage
    })
    |> dbg()

    {:noreply, socket}
  end
end
