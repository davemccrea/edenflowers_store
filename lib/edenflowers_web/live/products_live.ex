defmodule EdenflowersWeb.ProductsLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Store.Product

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    products = Product.get_all_for_store!()

    {:ok, assign(socket, products: products)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash}>
      <section class="bg-base-200 py-24">
        <div class="border-base-300/60 container border-t pt-16 pb-20 sm:pt-20 sm:pb-28">
          <div class="border-base-300/60 mb-12 border-b pb-6">
            <h2 class="font-serif text-base-content text-3xl sm:text-[2.4rem]">{gettext("All arrangements")}</h2>
            <p class="text-base-content/60 text-sm sm:text-base">
              {gettext("Soft palettes, precise silhouettes, and seasonal stems curated by our studio team.")}
            </p>
          </div>

          <%= if Enum.empty?(@products) do %>
            <div class="border-primary/40 bg-base-100 flex flex-col items-center gap-4 border border-dashed px-8 py-16 text-center">
              <.icon name="hero-sparkles" class="text-primary h-12 w-12" />
              <h3 class="font-serif text-2xl">{gettext("Fresh stems loading soon")}</h3>
              <p class="text-base-content/70 max-w-md text-sm sm:text-base">
                {gettext("We're refreshing our collection. Check back shortly for newly arranged bouquets ready to ship.")}
              </p>
            </div>
          <% else %>
            <ul class="grid gap-5 sm:grid-cols-2 xl:grid-cols-3 xl:gap-6" role="list">
              <li
                :for={product <- @products}
                class="group border-base-300/80 bg-base-100 relative flex transform flex-col overflow-hidden border transition duration-200 hover:scale-[1.01] hover:border-primary/60 hover:shadow-[0_12px_25px_rgba(15,23,42,0.05)]"
              >
                <.link
                  class="flex h-full flex-col"
                  navigate={~p"/product/#{product}"}
                  aria-labelledby={"product-#{product.id}"}
                >
                  <figure class="aspect-[4/5] relative overflow-hidden">
                    <img
                      src={product.image_slug}
                      alt={product.name}
                      class="h-full w-full object-cover transition duration-300 group-hover:scale-[1.05]"
                      width="1"
                      height="1"
                      loading="lazy"
                    />
                  </figure>

                  <div class="flex flex-1 flex-col justify-between gap-1 px-6 pt-6 pb-6 sm:px-7 sm:pb-8">
                    <h3
                      id={"product-#{product.id}"}
                      class="font-serif text-base-content text-[1.6rem] tracking-wide sm:text-[1.85rem]"
                    >
                      {product.name}
                    </h3>

                    <div class="text-base-content flex items-center justify-between">
                      <span class="text-base-content/70 text-sm sm:text-base">
                        {Edenflowers.Utils.format_money(product.cheapest_price)}
                      </span>
                      <span class="tracking-[0.3em] text-base-content/60 flex items-center gap-1 text-xs uppercase transition duration-200 group-hover:text-primary sm:text-sm">
                        {gettext("View")}
                        <.icon
                          name="hero-arrow-right"
                          class="h-4 w-4 transition-transform duration-150 ease-out group-hover:translate-x-1"
                        />
                      </span>
                    </div>
                  </div>
                </.link>
              </li>
            </ul>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
