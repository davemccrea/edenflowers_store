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
        <div class="container py-24 xl:max-w-[70vw]">
          <div class="mb-4 flex items-end justify-between gap-4 px-2">
            <h2 class="section-title">{~t"Featured Blooms"}</h2>

            <div class="hidden items-center gap-2 md:flex">
              <button
                type="button"
                class="embla__prev btn btn-circle btn-ghost"
                aria-label={~t"Previous"}
              >
                <.icon name="hero-chevron-left" class="h-5 w-5" />
              </button>
              <button
                type="button"
                class="embla__next btn btn-circle btn-ghost"
                aria-label={~t"Next"}
              >
                <.icon name="hero-chevron-right" class="h-5 w-5" />
              </button>
            </div>
          </div>

          <div class="embla">
            <div
              id="featured-blooms-viewport"
              phx-hook="FeaturedCarousel"
              phx-update="ignore"
              class="embla__viewport"
              role="region"
              aria-label={~t"Featured Blooms"}
            >
              <ul class="embla__container">
                <li :for={product <- @products} class="embla__slide">
                  <.link
                    navigate={~p"/product/#{product}"}
                    aria-labelledby={product.name}
                    class="group flex flex-col"
                  >
                    <%!-- The wrapping <div> is the morph source: a capture-
                         phase click listener in app.js sees `data-vt-name`
                         and stamps `view-transition-name: product-hero` on
                         it before LV navigates. The product page's <figure>
                         carries the same name as a static style, so the
                         browser pairs them and morphs the size/position. --%>
                    <div
                      class="mb-3 overflow-hidden rounded-lg"
                      data-vt-name="product-hero"
                    >
                      <picture>
                        <%!-- Mobile: 4:5 portrait crop for an immersive feel.
                             Desktop (sm+): 1:1 square so cards sit cleanly in a row. --%>
                        <source
                          media="(min-width: 640px)"
                          srcset={
                            product.image_slug |> Imgproxy.new() |> Imgproxy.resize(600, 600, type: "fill") |> to_string()
                          }
                        />
                        <img
                          src={
                            product.image_slug |> Imgproxy.new() |> Imgproxy.resize(600, 750, type: "fill") |> to_string()
                          }
                          alt={product.name}
                          class="aspect-[4/5] w-full object-cover transition duration-500 ease-out group-hover:scale-[1.03] sm:aspect-square"
                        />
                      </picture>
                    </div>
                    <div class="text-base-content flex flex-col items-center gap-1">
                      <h3
                        id={product.name}
                        class="card-title underline-offset-4 group-hover:decoration-(--color-accent-alt) group-hover:underline"
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

            <div class="embla__dots mt-4 hidden justify-center gap-2 sm:flex" />
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
            class="eyebrow text-base-content underline-offset-[6px] hover:decoration-(--color-accent-alt) hover:underline"
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
