defmodule EdenflowersWeb.ProductLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Store.{Product, LineItem}

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  def mount(%{"id" => id}, %{"order_id" => order_id}, socket) do
    {:ok, product} = Product.get_by_id(id, load: [:product_variants, :tax_rate])
    product_variants = product.product_variants

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
     |> assign(product_variants: product_variants)
     |> assign(selected_variant: selected_variant)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash}>
      <div class="container my-36">
        <.breadcrumb>
          <:item navigate={~p"/"} label={gettext("Home")} />
          <:item navigate={~p"/#store"} label={gettext("Store")} />
          <:item label={@product.name} />
        </.breadcrumb>

        <div class="grid gap-12 md:grid-cols-2 md:items-start">
          <%!-- Product Image --%>
          <figure class="aspect-square bg-base-200 relative w-full overflow-hidden rounded shadow-md">
            <img
              src={@selected_variant.image_slug}
              alt={"#{@product.name} #{String.capitalize(to_string(@selected_variant.size))}"}
              class="h-full w-full object-cover"
              width="1"
              height="1"
              loading="lazy"
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
              <.form for={%{}} phx-submit="submit" phx-change="change" class="flex flex-col gap-4">
                <.input
                  :let={option}
                  type="radio-card"
                  options={
                    Enum.map(
                      @product_variants,
                      &%{name: String.capitalize(to_string(&1.size)), value: &1.id, price: &1.price}
                    )
                  }
                  name="product_variant_id"
                  value={@selected_variant.id}
                  label={gettext("Select Size")}
                >
                  <div class="flex flex-col">
                    <span class="font-medium">{option.name}</span>
                    <span class="text-base-content/60 text-sm">
                      {Edenflowers.Utils.format_money(option.price)}
                    </span>
                  </div>
                </.input>

                <button type="submit" phx-click={JS.exec("phx-show", to: "#cart-drawer")} class="btn btn-primary btn-lg">
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

  def handle_event("change", %{"product_variant_id" => id}, socket) do
    variant = Enum.find(socket.assigns.product_variants, &(&1.id == id))
    {:noreply, assign(socket, selected_variant: variant)}
  end

  def handle_event("submit", _params, socket) do
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

    {:noreply, socket}
  end
end
