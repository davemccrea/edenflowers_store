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

      <section class="bg-cream relative overflow-hidden not-last:border-b" aria-labelledby="location-heading">
        <.flower
          name="flower-41"
          class="text-base-content/15 pointer-events-none absolute top-4 left-4 h-16 w-16 md:top-8 md:left-8 md:h-24 md:w-24"
        />
        <div class="grid md:grid-cols-2">
          <div class="flex flex-col px-4 pt-16 pb-8 sm:px-8 md:justify-center md:px-12 md:py-20 lg:px-20">
            <p class="eyebrow text-base-content/60 mb-4">{~t"Where to find us"}</p>
            <h2 id="location-heading" class="section-title mb-7">
              {~t"Made in Vaasa, Finland."}
            </h2>
            <p class="text-base-content/80 max-w-prose text-lg leading-relaxed">
              {~t"Cut and arranged the same day from a small shop on Kauppapuistikko. Eden Flowers delivers up to 20 km from Vaasa city centre — from €3, with free delivery within 5 km. The most competitive rates in the region."}
            </p>
          </div>

          <img
            src={
              "local:///home-vaasa-map.png"
              |> Imgproxy.new()
              |> Imgproxy.resize(800, 940, type: "fill")
              |> Imgproxy.set_extension("webp")
              |> to_string()
            }
            alt={~t"Map of Vaasa, Finland showing Eden Flowers' location at Kauppapuistikko 21"}
            loading="lazy"
            width="800"
            height="940"
            class="aspect-[6/7] max-h-[520px] h-full w-full object-cover md:aspect-auto"
          />
        </div>
      </section>

      <%!-- Pull quote --%>
      <section class="bg-forest not-last:border-b">
        <div class="container flex flex-col items-center gap-10 py-24 md:py-32">
          <.flower name="flower-30" class="text-forest-content/70 h-12 w-12" />
          <blockquote class="pull-quote text-forest-content max-w-4xl text-center">
            {~t"Crafted for those with discerning taste — flowers that blend quality and style and arrive perfectly arranged at your door."}
          </blockquote>
          <.link
            navigate={~p"/about"}
            class="eyebrow text-forest-content link-underline-hover-nav"
          >
            {~t"Learn more"}
          </.link>
        </div>
      </section>

      <%!-- Other services --%>
      <section class="not-last:border-b">
        <div class="container py-20 md:py-28">
          <h2 class="section-title mb-10">{~t"Beyond the storefront"}</h2>
          <div class="grid grid-cols-1 gap-4 md:grid-cols-3">
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
