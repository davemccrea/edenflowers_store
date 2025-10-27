defmodule EdenflowersWeb.HomeLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Store.Product

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    # TODO: get only featured products
    products = Product.get_all_for_store!()

    {:ok, socket |> assign(products: products)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash}>
      <section class="relative not-last:border-b">
        <img src="/images/image_1.jpg" class="h-[100vh] w-full object-cover" alt="" />

        <div class="container absolute inset-0 flex flex-col items-center justify-center gap-8 text-center">
          <h1 class="hero-heading text-image font-serif max-w-[20ch] tracking-wide">
            {gettext("Fresh flowers for everyday moments.")}
          </h1>
          <a href="#store" class="btn-primary btn btn-lg mx-auto">
            {gettext("Shop Now")}
          </a>
        </div>
      </section>

      <section id="store" class="not-last:border-b">
        <div class="m-auto py-24 xl:max-w-[70vw]">
          <h2 class="font-serif mb-4 px-2 text-3xl">{gettext("Featured Blooms")}</h2>

          <div
            id="product-slider"
            style="scrollbar-width: thin;"
            class="flex snap-x snap-mandatory overflow-x-auto px-2 pb-6"
          >
            <ul class="flex space-x-2 py-2">
              <li :for={product <- @products} class="w-3/8 flex-none snap-center xs:w-1/2 sm:w-72">
                <.link
                  navigate={~p"/product/#{product}"}
                  aria-labelledby={product.name}
                  class="flex flex-col transition duration-100 hover:opacity-90"
                >
                  <div class="mb-2 overflow-hidden rounded-lg">
                    <img src={product.image_slug} alt={product.name} class="aspect-square w-full object-cover" />
                  </div>
                  <div class="text-base-content flex flex-col items-center">
                    <h3 id={product.name} class="font-serif text-xl">{product.name}</h3>
                    <p class="text-sm">{Edenflowers.Utils.format_money(product.cheapest_price)}</p>
                  </div>
                </.link>
              </li>
            </ul>
          </div>
        </div>
      </section>

      <section class="not-last:border-b">
        <div class="container flex flex-col items-center gap-12 py-24">
          <h1 class="font-serif max-w-4xl text-center text-3xl font-light leading-10 sm:leading-14 md:text-4xl">
            {gettext(
              "Crafted for those with discerning taste, our flowers blend quality and style and arrive perfectly arranged at your door."
            )}
          </h1>
          <a class="font-bold uppercase tracking-wider underline underline-offset-4" href={~p"/#about"}>
            {gettext("Learn more")}
          </a>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
