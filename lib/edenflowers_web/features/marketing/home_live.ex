defmodule EdenflowersWeb.Marketing.HomeLive do
  @moduledoc """
  Public home page with the shop introduction and featured products.
  """

  use EdenflowersWeb, :live_view

  alias Edenflowers.Catalog
  alias Edenflowers.Format
  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Availability
  alias Edenflowers.Translations

  # Placeholder quotes to preview the layout; only rendered in dev until real reviews arrive.
  @sample_reviews_visible? Application.compile_env(:edenflowers, :dev_routes, false)
  @sample_reviews [
    %{
      quote: "The bouquet for my mum's 70th was even lovelier than the photo. She's still talking about it.",
      name: "Anna",
      source: "Google"
    },
    %{
      quote: "Jennie did the flowers for our wedding and understood exactly what we wanted from one conversation.",
      name: "Mikael and Sara",
      source: "Google"
    },
    %{
      quote: "Ordered at lunch, delivered the same afternoon. Fresh, generous and beautifully wrapped.",
      name: "Liisa",
      source: "Instagram"
    }
  ]

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(_params, _session, socket) do
    products = Catalog.list_featured_products!() |> Translations.translate()
    locale = Format.locale()

    {:ok,
     assign(socket,
       page_title: ~t"Florist in Vaasa",
       alternates: alternates("/#{language}"),
       page_description:
         ~t"Fresh flowers by Jennie at Eden Flowers in Vaasa: bouquets, flower subscriptions, wedding and funeral flowers. Free delivery within 5 km of Minimossen on selected bouquets.",
       json_ld: EdenflowersWeb.Business.florist(),
       products: products,
       reviews: if(@sample_reviews_visible?, do: @sample_reviews, else: []),
       subscribable_products: Catalog.list_subscribable_products!() |> Translations.translate(),
       price_from: price_from(Catalog.list_bouquets!(), locale),
       next_fulfillment: next_fulfillment(locale),
       delivery_fee: delivery_fee(locale)
     )}
  end

  defp price_from(products, locale) do
    case products |> Enum.map(& &1.cheapest_price) |> Enum.reject(&is_nil/1) do
      [] -> nil
      prices -> Format.storefront_price(Enum.min(prices, Decimal), locale)
    end
  end

  defp next_fulfillment(locale) do
    calendar = Fulfillment.get_shop_calendar!()
    now = Edenflowers.ShopTime.now()

    case Availability.next_open_date(calendar, now) do
      nil ->
        nil

      date ->
        if date == DateTime.to_date(now),
          do: ~t"Today, if you order by #{time = Format.time(calendar.order_deadline, locale)}",
          else: date |> Format.weekday_day_month(locale) |> String.capitalize()
    end
  end

  defp delivery_fee(locale) do
    case Fulfillment.distance_priced_delivery() do
      nil ->
        nil

      %{free_dist_km: km, base_price: base, price_per_km: per_km} when is_integer(km) and km > 0 ->
        ~t"#{base = Format.storefront_price(base, locale)} plus #{per_km = Format.storefront_price(per_km, locale)} per km. Free within #{km = km} km for chosen bouquets."

      %{base_price: base, price_per_km: per_km} ->
        ~t"#{base = Format.storefront_price(base, locale)} plus #{per_km = Format.storefront_price(per_km, locale)} per km."
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      current_user={@current_user}
      order={@order}
      flash={@flash}
      current_path={@current_path}
      alternates={@alternates}
    >
      <section class="relative overflow-hidden not-last:border-b">
        <.image
          src="local:///wedding/daniela_streng_1.jpg"
          alt=""
          width={1920}
          height={1080}
          sources={[%{media: "(max-width: 767px)", width: 1080, height: 1920}]}
          priority
          class="hero-zoom h-[75dvh] w-full object-cover md:h-dvh"
        />

        <div class="container absolute inset-0 flex flex-col justify-end pb-16 sm:pb-28 md:justify-center md:pb-0">
          <h1 class="hero-display hero-focus max-w-[16ch] italic text-white" style="--reveal-delay: 80ms;">
            <span class="sr-only">{~t"Flowers for every stage of life"}</span>
            <span aria-hidden="true">
              {~t"Flowers for"}
              <span class="hero-rotator">
                <span style="--i: 0;">{~t"every stage of life"}</span>
                <span style="--i: 1;">{~t"everyday moments"}</span>
                <span style="--i: 2;">{~t"a new arrival"}</span>
                <span style="--i: 3;">{~t"your wedding day"}</span>
                <span style="--i: 4;">{~t"every stage of life"}</span>
              </span>
            </span>
          </h1>
          <p class="hero-reveal mt-6 max-w-md text-lg leading-relaxed text-white" style="--reveal-delay: 600ms;">
            <%= if @price_from do %>
              {~t"Bouquets made by hand the day they're delivered, from #{price = @price_from}."}
            <% else %>
              {~t"Bouquets made by hand the day they're delivered."}
            <% end %>
          </p>
          <div class="hero-reveal mt-10" style="--reveal-delay: 750ms;">
            <.button
              navigate={~q"/#{language}/store"}
              variant="inverse"
              size="lg"
              class="group w-fit"
            >
              {~t"Choose bouquet"}
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

      <nav aria-label={~t"What are the flowers for?"} class="not-last:border-b">
        <ul class="container flex flex-wrap items-center justify-center gap-x-10 gap-y-4 py-8">
          <li>
            <.link navigate={~q"/#{language}/store"} class="eyebrow link-underline-hover touch-target">
              {~t"Bouquets"}
            </.link>
          </li>
          <li :if={@subscribable_products != []}>
            <a href="#subscription" class="eyebrow link-underline-hover touch-target">{~t"Flower subscription"}</a>
          </li>
          <li>
            <.link navigate={~q"/#{language}/condolences"} class="eyebrow link-underline-hover touch-target">
              {~t"Funeral flowers"}
            </.link>
          </li>
          <li>
            <.link navigate={~q"/#{language}/weddings"} class="eyebrow link-underline-hover touch-target">
              {~t"Weddings"}
            </.link>
          </li>
          <li>
            <.link navigate={~q"/#{language}/courses"} class="eyebrow link-underline-hover touch-target">
              {~t"Courses"}
            </.link>
          </li>
        </ul>
      </nav>

      <section :if={@products != []} id="store" class="not-last:border-b">
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
              phx-hook=".FeaturedCarousel"
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
                    navigate={~q"/#{language}/product/#{product}"}
                    locale={Edenflowers.Format.locale()}
                  />
                </div>
              </div>
            </div>
            <script :type={Phoenix.LiveView.ColocatedHook} name=".FeaturedCarousel">
              import EmblaCarousel from "@/vendor/embla-carousel.esm";

              /**
               * Carousel for the Featured Blooms section.
               *
               * Markup contract (set in HomeLive):
               *   <div class="embla">
               *     <div class="embla__viewport" phx-hook=".FeaturedCarousel" id="...">
               *       <div class="embla__container">
               *         <div class="embla__slide" role="group">...</div>
               *       </div>
               *     </div>
               *     <button class="embla__prev">…</button>
               *     <button class="embla__next">…</button>
               *     <div class="embla__dots"></div>
               *   </div>
               */
              export default {
                mounted() {
                  // Buttons live in the section heading (sibling of .embla), so we scope
                  // the lookup to the enclosing <section> rather than .embla itself.
                  const scope = this.el.closest("section") || document;
                  this.prevBtn = scope.querySelector(".embla__prev");
                  this.nextBtn = scope.querySelector(".embla__next");
                  this.dotsNode = scope.querySelector(".embla__dots");
                  this.dotNodes = [];

                  // Reduced-motion users skip the per-frame focal-point work entirely.
                  // The breakpoint above which the effect is disabled is handled in CSS.
                  this.reducedMotion = window.matchMedia(
                    "(prefers-reduced-motion: reduce)",
                  ).matches;

                  // slidesToScroll: 1 on mobile, 'auto' on >=md so an arrow click jumps a
                  // full page of cards on desktop.
                  this.embla = EmblaCarousel(this.el, {
                    align: "center",
                    containScroll: "trimSnaps",
                    slidesToScroll: 1,
                    breakpoints: {
                      "(min-width: 768px)": { slidesToScroll: "auto" },
                    },
                  });

                  this.boundOnSelect = this.onSelect.bind(this);
                  this.boundOnReInit = this.onReInit.bind(this);
                  this.boundOnTween = this.onTween.bind(this);

                  if (this.prevBtn) {
                    this.prevBtn.addEventListener("click", () => this.embla.scrollPrev());
                  }
                  if (this.nextBtn) {
                    this.nextBtn.addEventListener("click", () => this.embla.scrollNext());
                  }

                  this.buildDots();
                  this.setTweenFactor();
                  this.embla.on("select", this.boundOnSelect);
                  this.embla.on("reInit", this.boundOnReInit);
                  this.embla.on("scroll", this.boundOnTween);
                  this.embla.on("slideFocus", this.boundOnTween);
                  this.onSelect();
                  this.onTween();
                },

                updated() {
                  if (this.embla) this.embla.reInit();
                },

                destroyed() {
                  if (this.embla) this.embla.destroy();
                },

                /**
                 * Compute the focal-point falloff multiplier. Scaling by snapList length
                 * keeps the effect feeling consistent whether there are 3 or 30 snaps —
                 * matches Embla's predefined Tween Scale / Tween Opacity examples.
                 */
                setTweenFactor() {
                  const TWEEN_FACTOR_BASE = 0.6;
                  this.tweenFactor = TWEEN_FACTOR_BASE * this.embla.scrollSnapList().length;
                },

                /**
                 * Per-frame focal-point effect: write each slide's distance-from-center
                 * (clamped 0..1) to a CSS custom property so CSS can scale/fade neighbours.
                 * Iterates by snap index and resolves slides via slideRegistry — correct
                 * under slidesToScroll:'auto' grouping at md+. CSS gates which breakpoint
                 * the effect actually applies at.
                 */
                onTween(eventName) {
                  if (this.reducedMotion) return;
                  const engine = this.embla.internalEngine();
                  const scrollProgress = this.embla.scrollProgress();
                  const slidesInView = this.embla.slidesInView();
                  const slideNodes = this.embla.slideNodes();
                  const isScrollEvent = eventName === "scroll";

                  this.embla.scrollSnapList().forEach((scrollSnap, snapIndex) => {
                    const diffToTarget = scrollSnap - scrollProgress;

                    engine.slideRegistry[snapIndex].forEach((slideIndex) => {
                      // Per-frame: skip off-screen slides. On reInit / slideFocus / mount
                      // we update everyone so freshly-revealed slides paint correctly.
                      if (isScrollEvent && !slidesInView.includes(slideIndex)) return;
                      const progress = Math.min(Math.abs(diffToTarget * this.tweenFactor), 1);
                      slideNodes[slideIndex].style.setProperty(
                        "--embla-progress",
                        progress.toFixed(3),
                      );
                    });
                  });
                },

                buildDots() {
                  if (!this.dotsNode) return;
                  // Localized template comes from a data attr on the viewport. Falls back
                  // to English if missing so the carousel still works.
                  // Sentinel "__N__" is replaced client-side. Using %{n} would trigger
                  // Gettext binding-validation warnings server-side at every render.
                  const tpl = this.el.dataset.dotLabelTemplate || "Go to slide __N__";
                  const snapList = this.embla.scrollSnapList();
                  this.dotsNode.innerHTML = snapList
                    .map(
                      (_, i) =>
                        `<button type="button" class="embla__dot" aria-label="${tpl.replace("__N__", i + 1)}" aria-current="false"></button>`,
                    )
                    .join("");
                  this.dotNodes = Array.from(this.dotsNode.querySelectorAll(".embla__dot"));
                  this.dotNodes.forEach((node, i) => {
                    node.addEventListener("click", () => this.embla.scrollTo(i));
                  });
                },

                onSelect() {
                  const selected = this.embla.selectedScrollSnap();
                  this.dotNodes.forEach((node, i) => {
                    const isSelected = i === selected;
                    node.classList.toggle("embla__dot--selected", isSelected);
                    node.setAttribute("aria-current", isSelected ? "true" : "false");
                  });
                  const canScroll = this.embla.canScrollPrev() || this.embla.canScrollNext();
                  this.el
                    .closest("section")
                    ?.classList.toggle("embla--no-scroll", !canScroll);
                  if (this.prevBtn) this.prevBtn.disabled = !this.embla.canScrollPrev();
                  if (this.nextBtn) this.nextBtn.disabled = !this.embla.canScrollNext();
                },

                onReInit() {
                  this.buildDots();
                  this.setTweenFactor();
                  this.onSelect();
                  this.onTween();
                },
              };
            </script>

            <div class="embla__dots mt-4 hidden justify-center gap-2 sm:flex" />
          </div>

          <div class="mt-10 text-center">
            <.link navigate={~q"/#{language}/store"} class="eyebrow link-underline-hover touch-target">
              {~t"Shop all flowers"}
            </.link>
          </div>
        </div>
      </section>

      <section class="not-last:border-b">
        <div class="container py-12 md:py-16">
          <p class="eyebrow text-base-content/70 mb-8 text-center">{~t"Trusted by"}</p>
          <ul class="flex flex-wrap items-center justify-center gap-x-16 gap-y-10 md:gap-x-24">
            <li>
              <a
                href="https://www.dermosil.com/"
                class="touch-target block"
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
              <a
                href="https://sfp.fi/"
                class="touch-target block"
                target="_blank"
                rel="noopener noreferrer"
                aria-label="SFP RKP"
              >
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
                class="touch-target block"
                target="_blank"
                rel="noopener noreferrer"
                aria-label={~t"Evangelical Lutheran Church of Finland"}
              >
                <img
                  src="/images/logo-evl.svg"
                  alt={~t"Evangelical Lutheran Church of Finland"}
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
                class="touch-target block"
                target="_blank"
                rel="noopener noreferrer"
                aria-label="Bonnier News Finland"
              >
                <img
                  src="/images/logo-bonnier-news.png"
                  alt="Bonnier News Finland"
                  width="104"
                  height="32"
                  loading="lazy"
                  decoding="async"
                  class="h-8 w-auto opacity-50 grayscale transition-opacity hover:opacity-70"
                />
              </a>
            </li>
          </ul>
        </div>
      </section>

      <section :if={@reviews != []} class="not-last:border-b" aria-labelledby="reviews-heading">
        <div class="container py-20 md:py-28">
          <h2 id="reviews-heading" class="section-title mb-12">{~t"What customers say"}</h2>
          <ul class="grid gap-12 md:grid-cols-3 md:gap-8">
            <li :for={review <- @reviews}>
              <figure class="flex h-full flex-col gap-6">
                <.flower name="flower-30" class="text-base-content/30 h-8 w-8" />
                <blockquote class="font-serif text-balance text-xl leading-snug md:text-2xl">
                  {review.quote}
                </blockquote>
                <figcaption class="eyebrow text-base-content/70 mt-auto">
                  {review.name} · {review.source}
                </figcaption>
              </figure>
            </li>
          </ul>
        </div>
      </section>

      <section class="bg-cream relative not-last:border-b" aria-labelledby="location-heading">
        <.flower
          name="flower-41"
          class="text-base-content/15 pointer-events-none absolute top-4 left-4 h-16 w-16 md:top-8 md:left-8 md:h-24 md:w-24"
        />
        <div class="grid md:grid-cols-[3fr_2fr]">
          <div class="flex flex-col px-4 pt-16 pb-8 sm:px-8 md:justify-center md:px-12 md:py-20 lg:px-20">
            <h2 id="location-heading" class="section-title mb-8">{~t"Delivery and pickup"}</h2>
            <dl class="grid max-w-prose gap-6 text-lg leading-relaxed">
              <div :if={@next_fulfillment}>
                <dt class="eyebrow text-base-content/70 mb-1">{~t"Next available day"}</dt>
                <dd>{@next_fulfillment}</dd>
              </div>
              <div :if={@delivery_fee}>
                <dt class="eyebrow text-base-content/70 mb-1">{~t"Delivery"}</dt>
                <dd>{@delivery_fee}</dd>
              </div>
              <div>
                <dt class="eyebrow text-base-content/70 mb-1">{~t"Pickup"}</dt>
                <dd>{~t"Free from Minimossen."}</dd>
              </div>
            </dl>
          </div>

          <.image
            src="local:///home-vaasa-map.png"
            alt={~t"Map of Vaasa, Finland with Minimossen pinned"}
            width={1600}
            height={1880}
            sizes="(min-width: 768px) 40vw, 100vw"
            class="aspect-[4/3] h-full max-h-80 w-full object-cover md:aspect-auto md:max-h-none"
          />
        </div>
      </section>

      <section
        :if={@subscribable_products != []}
        id="subscription"
        class="not-last:border-b"
        aria-labelledby="subscription-heading"
      >
        <div class="container py-20 md:py-28">
          <h2 id="subscription-heading" class="section-title mb-6">{~t"Flower subscription"}</h2>
          <p class="text-base-content/80 mb-12 max-w-prose text-lg leading-relaxed">
            {~t"Fresh flowers every week, every two weeks or every four weeks, delivered or ready to pick up. Pause, change or stop from your account up to #{days = Edenflowers.Orders.Subscription.lead_days() + 1} days before a bouquet."}
          </p>
          <div class="grid grid-cols-2 gap-4 md:grid-cols-4">
            <.product_card
              :for={product <- @subscribable_products}
              product={product}
              navigate={~q"/#{language}/product/#{product}"}
              locale={Edenflowers.Format.locale()}
            />
          </div>
        </div>
      </section>

      <section class="bg-forest not-last:border-b">
        <div class="grid md:grid-cols-2">
          <.image
            src="local:///jennie_2.jpg"
            alt="Jennie"
            width={1500}
            height={1000}
            sizes="(min-width: 768px) 50vw, 100vw"
            class="aspect-[4/5] max-h-[640px] object-[60%_center] h-full w-full object-cover md:aspect-auto md:h-[640px]"
          />

          <div class="flex flex-col items-start gap-10 px-4 py-20 sm:px-8 md:justify-center md:px-12 lg:px-20">
            <.flower name="flower-30" class="text-forest-content/70 h-12 w-12" />
            <p class="pull-quote text-forest-content max-w-xl">
              {~t"Hi, I'm Jennie. I make every arrangement myself at my shop in Minimossen, from a bouquet for your kitchen table to flowers for your wedding."}
            </p>
            <.link
              navigate={~q"/#{language}/about"}
              class="eyebrow text-forest-content link-underline-hover touch-target"
            >
              {~t"Meet Jennie"}
            </.link>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
