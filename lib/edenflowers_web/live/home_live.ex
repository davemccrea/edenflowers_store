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

        <div class="container absolute inset-0 flex flex-col justify-end pb-20 sm:pb-28 md:justify-center md:pb-0">
          <h1 class="hero-display hero-reveal max-w-[16ch] text-white" style="--reveal-delay: 80ms;">
            {~t"Fresh flowers for everyday moments"}
          </h1>
          <div class="hero-reveal mt-10" style="--reveal-delay: 280ms;">
            <.link
              navigate={~p"/store"}
              class="border-white/80 font-sans tracking-[0.18em] inline-flex w-fit border px-7 py-3 text-sm uppercase text-white transition hover:text-base-content hover:bg-white"
            >
              {~t"Shop Now"}
            </.link>
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
                aria-label={~t"Previous slide"}
                aria-controls="featured-blooms-viewport"
              >
                <.icon name="hero-chevron-left" class="h-5 w-5" />
              </button>
              <button
                type="button"
                class="embla__next btn btn-circle btn-ghost"
                aria-label={~t"Next slide"}
                aria-controls="featured-blooms-viewport"
              >
                <.icon name="hero-chevron-right" class="h-5 w-5" />
              </button>
            </div>
          </div>

          <div
            class="embla"
            role="group"
            aria-roledescription="carousel"
            aria-label={~t"Featured Blooms"}
          >
            <div
              id="featured-blooms-viewport"
              phx-hook="FeaturedCarousel"
              phx-update="ignore"
              class="embla__viewport"
              data-dot-label-template={~t"Go to slide __N__"}
            >
              <ul class="embla__container">
                <li
                  :for={{product, idx} <- Enum.with_index(@products)}
                  class="embla__slide"
                  role="group"
                  aria-roledescription="slide"
                  aria-label={"#{idx + 1} / #{length(@products)}: #{product.name}"}
                >
                  <.product_card product={product} navigate={~p"/product/#{product}"} />
                </li>
              </ul>
            </div>

            <div class="embla__dots mt-4 hidden justify-center gap-2 sm:flex" />
          </div>
        </div>
      </section>

      <%!-- Location: copy anchored to container left, map bleeds to viewport right --%>
      <section class="bg-cream overflow-hidden not-last:border-b" aria-labelledby="location-heading">
        <div class="grid grid-cols-1 items-center gap-12 md:grid-cols-[1fr_1.1fr] md:gap-16 lg:gap-24">
          <div class="container py-20 md:py-28 md:pr-0">
            <div class="flex flex-col gap-8 md:max-w-[28ch] md:ml-auto md:pl-8">
              <p class="eyebrow text-base-content/60">{~t"Where to find us"}</p>
              <h2 id="location-heading" class="section-title">
                {~t"Made in Vaasa, Finland."}
              </h2>
              <nav aria-label={~t"Location links"} class="flex flex-wrap gap-x-8 gap-y-3 pt-2">
                <.link navigate={~p"/contact"} class="link-underline-hover-nav">
                  {~t"Visit the shop"}
                </.link>
                <.link navigate={~p"/faq"} class="link-underline-hover-nav">
                  {~t"Delivery info"}
                </.link>
              </nav>
            </div>
          </div>

          <%!--
            Map slot — bleeds to the viewport right edge on desktop.

            To populate: export a static PNG from Mapbox Studio at 1200×1400,
            center 63.0951, 21.6165, zoom ~11.5, with a muted editorial style
            (paper land matching --color-cream, ink water close to --color-forest,
            hairline roads, one honey marker on Kauppapuistikko 21, POIs off,
            labels minimal). Save to priv/static/images/home-vaasa-map.png,
            then replace the placeholder <div> below with:

              <img
                src={~p"/images/home-vaasa-map.png"}
                alt={~t"Map showing Eden Flowers' location in Vaasa, Finland"}
                loading="lazy"
                width="1200"
                height="1400"
                class="aspect-[6/7] w-full h-full object-cover"
              />
          --%>
          <div
            role="img"
            aria-label={~t"Map placeholder for Eden Flowers' location in Vaasa, Finland"}
            class="border-base-content/12 bg-base-100/40 aspect-[6/7] flex items-center justify-center border md:aspect-auto md:min-h-[28rem] md:self-stretch md:border-r-0"
          >
            <p class="eyebrow text-base-content/40">{~t"Map of Vaasa"}</p>
          </div>
        </div>
      </section>

      <%!-- Pull quote --%>
      <section class="bg-forest not-last:border-b">
        <div class="container flex flex-col items-center gap-10 py-24 md:py-32">
          <blockquote class="pull-quote text-forest-content max-w-4xl text-center">
            {~t"Crafted for those with discerning taste, our flowers blend quality and style and arrive perfectly arranged at your door."}
          </blockquote>
          <.link
            navigate={~p"/about"}
            class="eyebrow text-forest-content link-underline-hover-nav"
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
