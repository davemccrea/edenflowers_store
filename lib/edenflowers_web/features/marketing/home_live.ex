defmodule EdenflowersWeb.Marketing.HomeLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Catalog

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    products = Catalog.list_featured_products!()

    {:ok, socket |> assign(products: products)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <section class="relative overflow-hidden not-last:border-b">
        <.image
          src="local:///wedding/daniela_streng_1.jpg"
          alt=""
          width={1920}
          height={1080}
          sources={[%{media: "(max-width: 767px)", width: 1080, height: 1920}]}
          priority
          class="hero-zoom h-dvh w-full object-cover"
        />

        <div class="container absolute inset-0 flex flex-col justify-end pb-20 sm:pb-28 md:justify-center md:pb-0">
          <h1 class="hero-display hero-reveal max-w-[16ch] italic text-white" style="--reveal-delay: 80ms;">
            {~t"Flowers for everyday moments"}
          </h1>
          <div class="hero-reveal mt-10" style="--reveal-delay: 280ms;">
            <.button
              navigate={~p"/store"}
              variant="inverse"
              size="lg"
              class="group w-fit"
            >
              {~t"Shop Now"}
              <.icon
                name="hero-arrow-right-mini"
                class="h-4 w-4 transition-transform duration-300 ease-out group-hover:translate-x-1"
              />
            </.button>
          </div>
        </div>

        <p class="text-white/80 absolute right-4 bottom-3 text-xs">
          {~t"Photo:"}
          <a
            href="https://www.danielastreng.com/"
            target="_blank"
            rel="noopener noreferrer"
            class="link-underline-hover hover:text-white"
          >
            Daniela Streng
          </a>
        </p>
      </section>

      <section id="store" class="not-last:border-b">
        <div class="container py-24 xl:max-w-[70vw]">
          <div class="mb-4 flex items-end justify-between gap-4 px-2">
            <h2 class="section-title">{~t"Favourites"}</h2>

            <div class="hidden items-center gap-2 md:flex">
              <.icon_button
                type="button"
                class="embla__prev"
                aria_label={~t"Previous slide"}
                aria-controls="featured-blooms-viewport"
              >
                <.icon name="hero-chevron-left" class="h-5 w-5" />
              </.icon_button>
              <.icon_button
                type="button"
                class="embla__next"
                aria_label={~t"Next slide"}
                aria-controls="featured-blooms-viewport"
              >
                <.icon name="hero-chevron-right" class="h-5 w-5" />
              </.icon_button>
            </div>
          </div>

          <div
            class="embla"
            role="group"
            aria-roledescription="carousel"
            aria-label={~t"Favourites"}
          >
            <div
              id="featured-blooms-viewport"
              phx-hook="FeaturedCarousel"
              phx-update="ignore"
              class="embla__viewport"
              data-dot-label-template={~t"Go to slide __N__"}
            >
              <div class="embla__container">
                <div
                  :for={{product, idx} <- Enum.with_index(@products)}
                  class="embla__slide"
                  role="group"
                  aria-roledescription="slide"
                  aria-label={"#{idx + 1} / #{length(@products)}: #{product.name}"}
                >
                  <.product_card
                    product={product}
                    navigate={~p"/product/#{product}"}
                    locale={Edenflowers.Format.locale()}
                  />
                </div>
              </div>
            </div>

            <div class="embla__dots mt-4 hidden justify-center gap-2 sm:flex" />
          </div>
        </div>
      </section>

      <section class="bg-cream relative not-last:border-b" aria-labelledby="location-heading">
        <.flower
          name="flower-41"
          class="text-base-content/15 pointer-events-none absolute top-4 left-4 h-16 w-16 md:top-8 md:left-8 md:h-24 md:w-24"
        />
        <div class="grid md:grid-cols-2">
          <div class="flex flex-col px-4 pt-16 pb-8 sm:px-8 md:justify-center md:px-12 md:py-20 lg:px-20">
            <p id="location-heading" class="eyebrow text-base-content/70 mb-4">{~t"Made in Minimossen"}</p>
            <p class="text-base-content/80 max-w-prose text-lg leading-relaxed">
              {~t"Every arrangement is made fresh to order, and delivery is free within 5 km of Minimossen."}
            </p>
          </div>

          <.image
            src="local:///home-vaasa-map.png"
            alt={~t"Map of Vaasa, Finland with Minimossen pinned"}
            width={1600}
            height={1880}
            sizes="(min-width: 768px) 50vw, 100vw"
            class="aspect-[6/7] max-h-[520px] h-full w-full object-cover md:aspect-auto"
          />
        </div>
      </section>

      <section class="bg-forest not-last:border-b">
        <div class="grid md:grid-cols-2">
          <.image
            src="local:///jennie_99.jpg"
            alt="Jennie"
            width={1080}
            height={1350}
            sizes="(min-width: 768px) 50vw, 100vw"
            class="aspect-[4/5] max-h-[640px] h-full w-full object-cover md:aspect-auto"
          />

          <div class="flex flex-col items-start gap-10 px-4 py-20 sm:px-8 md:justify-center md:px-12 lg:px-20">
            <.flower name="flower-30" class="text-forest-content/70 h-12 w-12" />
            <p class="pull-quote text-forest-content max-w-xl">
              {~t"Hi, I'm Jennie. I've been making flowers in Vaasa since 2018, and every arrangement still passes through my hands."}
            </p>
            <.link
              navigate={~p"/about"}
              class="eyebrow text-forest-content link-underline-hover"
            >
              {~t"Learn more"}
            </.link>
          </div>
        </div>
      </section>

      <section class="not-last:border-b">
        <div class="container py-20 md:py-28">
          <h2 class="section-title mb-10">{~t"Beyond bouquets"}</h2>
          <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
            <.category_tile
              navigate={~p"/weddings"}
              label={~t"Weddings"}
              image_src="local:///wedding/bjorn_yrjans.jpg"
            />
            <.category_tile
              navigate={~p"/courses"}
              label={~t"Courses"}
              image_src="local:///image_1.jpg"
            />
          </div>
          <%!-- Stands in for a condolences tile until there is a real photograph of funeral work. --%>
          <p class="tile-title text-balance mt-12 max-w-2xl">
            {~t"Ordering for a funeral? I deliver to churches and chapels in Vaasa and Korsholm."}
            <.link navigate={~p"/condolences"} class="link-underline-static-body whitespace-nowrap">
              {~t"Funeral flowers"}
            </.link>
          </p>
        </div>
      </section>

      <section class="not-last:border-b">
        <div class="container py-20 md:py-28">
          <p class="eyebrow text-base-content/70 mb-12 text-center">{~t"Trusted by"}</p>
          <ul class="flex flex-wrap items-center justify-center gap-x-16 gap-y-10 md:gap-x-24">
            <li>
              <a
                href="https://www.dermosil.com/"
                class="block"
                target="_blank"
                rel="noopener noreferrer"
                aria-label="Dermosil"
              >
                <img
                  src="/images/logo-dermosil.svg"
                  alt="Dermosil"
                  width="230"
                  height="33"
                  loading="lazy"
                  decoding="async"
                  class="h-7 w-auto opacity-50 grayscale transition-opacity hover:opacity-70"
                />
              </a>
            </li>
            <li>
              <a href="https://sfp.fi/" class="block" target="_blank" rel="noopener noreferrer" aria-label="SFP RKP">
                <img
                  src="/images/logo-sfp.svg"
                  alt="SFP RKP"
                  width="182"
                  height="40"
                  loading="lazy"
                  decoding="async"
                  class="h-8 w-auto opacity-50 grayscale transition-opacity hover:opacity-70"
                />
              </a>
            </li>
            <li>
              <a
                href="https://evl.fi/en/"
                class="block"
                target="_blank"
                rel="noopener noreferrer"
                aria-label="Evangelical Lutheran Church of Finland"
              >
                <img
                  src="/images/logo-evl.svg"
                  alt="Evangelical Lutheran Church of Finland"
                  width="363"
                  height="81"
                  loading="lazy"
                  decoding="async"
                  class="h-8 w-auto opacity-50 grayscale transition-opacity hover:opacity-70"
                />
              </a>
            </li>
            <li>
              <a
                href="https://bnf.fi/"
                class="block"
                target="_blank"
                rel="noopener noreferrer"
                aria-label="Bonnier News Finland"
              >
                <.image
                  src="local:///logo-bonnier-news.png"
                  alt="Bonnier News Finland"
                  width={104}
                  height={32}
                  crop_type="fit"
                  class="h-8 w-auto opacity-50 grayscale transition-opacity hover:opacity-70"
                />
              </a>
            </li>
          </ul>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
