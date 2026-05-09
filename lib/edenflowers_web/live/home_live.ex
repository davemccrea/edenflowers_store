defmodule EdenflowersWeb.HomeLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Store.Product

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    products = Product.get_featured!()

    {:ok, socket |> assign(products: products)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <section class="relative overflow-hidden not-last:border-b">
        <img
          src={"local:///image_1.jpg" |> Imgproxy.new() |> Imgproxy.resize(1920, 1080, type: "fill") |> to_string()}
          class="h-[100vh] w-full object-cover"
          alt=""
        />

        <%!-- Localised legibility wash: a soft radial darkens the area behind
             the headline block (mobile bottom-left, desktop centre-left),
             leaving the rest of the photo bright. --%>
        <div
          class="pointer-events-none absolute inset-0 md:hidden"
          style="background: radial-gradient(closest-corner at 28% 78%, rgba(0,0,0,0.55), rgba(0,0,0,0) 65%);"
        />
        <div
          class="pointer-events-none absolute inset-0 hidden md:block"
          style="background: radial-gradient(closest-corner at 25% 55%, rgba(0,0,0,0.5), rgba(0,0,0,0) 55%);"
        />

        <div class="container absolute inset-0 flex flex-col justify-end pb-20 sm:pb-28 md:justify-center md:pb-0">
          <h1 class="hero-display hero-reveal max-w-[16ch] text-white" style="--reveal-delay: 80ms;">
            {~t"Fresh flowers for everyday moments"}
          </h1>
          <div class="hero-reveal" style="--reveal-delay: 280ms;">
            <.button href="#store" variant="primary" size="lg" class="mt-10 w-fit gap-2 px-8">
              {~t"Shop Now"} <span aria-hidden="true">→</span>
            </.button>
          </div>
        </div>
      </section>

      <section id="store" class="not-last:border-b">
        <div class="m-auto py-24 xl:max-w-[70vw]">
          <h2 class="section-title mb-4 px-2">{~t"Featured Blooms"}</h2>

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
                  class="group flex flex-col"
                >
                  <div class="mb-3 overflow-hidden rounded-lg">
                    <img
                      src={product.image_slug |> Imgproxy.new() |> Imgproxy.resize(600, 600, type: "fill") |> to_string()}
                      alt={product.name}
                      class="aspect-square w-full object-cover transition duration-500 ease-out group-hover:scale-[1.03]"
                    />
                  </div>
                  <div class="text-base-content flex flex-col items-center gap-1">
                    <h3
                      id={product.name}
                      class="card-title link-underline-group-hover-display"
                    >
                      {product.name}
                    </h3>
                    <p class="text-base-content/70 text-sm">
                      {Edenflowers.Utils.format_money(product.cheapest_price)}
                    </p>
                  </div>
                </.link>
              </li>
            </ul>
          </div>
        </div>
      </section>

      <%!-- Pull quote --%>
      <section class="bg-pastel-3 not-last:border-b">
        <div class="container flex flex-col items-center gap-10 py-24 md:py-32">
          <blockquote class="pull-quote text-base-content/90 max-w-4xl text-center">
            {~t"Crafted for those with discerning taste, our flowers blend quality and style and arrive perfectly arranged at your door."}
          </blockquote>
          <.link
            navigate={~p"/about"}
            class="eyebrow text-base-content link-underline-hover-nav"
          >
            {~t"Learn more"}
          </.link>
        </div>
      </section>

      <%!-- Category tiles --%>
      <section class="bg-base-200 not-last:border-b">
        <div class="container py-20 md:py-28">
          <h2 class="section-title mb-10">{~t"Start Here"}</h2>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <.category_tile
              navigate={~p"/store"}
              label={~t"Store"}
              image_src="https://placehold.co/800x600/e8e0d8/888?text=Store"
            />
            <.category_tile
              navigate={~p"/weddings"}
              label={~t"Weddings"}
              image_src="https://placehold.co/800x600/e8e0d8/888?text=Weddings"
            />
            <.category_tile
              navigate={~p"/courses"}
              label={~t"Courses"}
              image_src="https://placehold.co/800x600/e8e0d8/888?text=Courses"
            />
            <.category_tile
              navigate={~p"/condolences"}
              label={~t"Condolences"}
              image_src="https://placehold.co/800x600/e8e0d8/888?text=Condolences"
            />
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
