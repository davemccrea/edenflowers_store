defmodule EdenflowersWeb.Marketing.HomeLive do
  @moduledoc """
  Public home page with the shop introduction and featured products.
  """

  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Marketing.CustomerQuote
  import EdenflowersWeb.Marketing.TrustedBy

  alias Edenflowers.Catalog
  alias Edenflowers.Format
  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Availability
  alias Edenflowers.Translations

  # Complete-sentence excerpts from feedback.md, preserving the customer's wording and emojis.
  # `en` is shown beneath the original on /en only. `occasion` is set only where the message names it.
  @review_pages [
    [
      %{
        quote:
          "Vi var såååå nöjda med både arrangemangen och speciellt av allt brudbuketten! Också kostymblommorna, hårbanden o tärnbuketterna var fantstiska! 💐😍 Buketten lyfte liksom bilderna, och det blev bättre än vad vi hade hoppats på!",
        en:
          "We were soooo happy with both the arrangements and especially the bridal bouquet! The buttonholes, hairbands and bridesmaids' bouquets were fantastic too! 💐😍 The bouquet really lifted the photos, and it turned out better than we'd hoped!",
        name: "Fanny",
        occasion: :wedding,
        lang: "sv"
      },
      %{
        quote:
          "Kiitos paljon ihanista hääkukista. Ne olivat täydellisemmät kuin osasin edes toivoa. 😍 Sopivat mielestäni täysin myös kokonaisuuteen ja tyyliini, kiitos siis niistä",
        en:
          "Thank you so much for the lovely wedding flowers. They were more perfect than I could have hoped for. 😍 I think they also suited the overall look and my style perfectly, so thank you for them",
        name: "Aino",
        occasion: :wedding,
        lang: "fi"
      },
      %{
        quote:
          "Ville bara berätta hur prisvärda och fina dina buketter är jämfört med konkurrenterna. Dina är ju superfina och unika och enligt mamma och pappa så håller dom jättebra!",
        en:
          "Just wanted to say how good value and lovely your bouquets are compared to the competition. Yours are so beautiful and unique, and mum and dad say they last really well!",
        name: "Minéa",
        lang: "sv"
      }
    ],
    [
      %{
        quote:
          "Var så smidigt att du kunde ta dej dit under dagen och fixa i lugn och ro och jag kände aldrig någon stress över att blommorna inte skulle vara perfekta under dagen så tack för det! 💐💕",
        en:
          "It was so easy that you could come over during the day and set up in peace and I never once worried the flowers wouldn't be perfect during the day so thank you for that! 💐💕",
        name: "Julia",
        occasion: :wedding,
        lang: "sv"
      },
      %{
        quote:
          "Kiitos vielä ristiäisten kukista, ne olivat todella kauniit! 😍 Teit meille kukat häihimme pari vuotta sitten, joten oli ihana saada kukat sinulta myös tyttäremme ensimmäiseen suureen juhlaan. Ja miten upeat kukat jälleen saimmekaan. Kiitos paljon.",
        en:
          "Thank you again for the christening flowers, they were really beautiful! 😍 You did the flowers for our wedding a couple of years ago, so it was lovely to have your flowers for our daughter's first big celebration too. And what gorgeous flowers we received once again. Thank you so much.",
        name: "Aino",
        occasion: :christening,
        lang: "fi"
      },
      %{
        quote: "Så fint att du finns - du är en riktig räddare i nöden👍",
        en: "So glad you're here - you're a real lifesaver👍",
        name: "Elinor",
        lang: "sv"
      }
    ],
    [
      %{
        quote:
          "Så tusen tusen tack att du fick det fixat exakt som jag hade tänkt! Det blev både elegant, vackert och romantiskt! Så tack❤️",
        en:
          "So thank you so, so much for getting it exactly as I'd imagined! It was elegant, beautiful and romantic! So thank you❤️",
        name: "Lena",
        occasion: :wedding,
        lang: "sv"
      },
      %{
        quote:
          "Brudbuketten var ännu vackrare än vad jag hade förväntat mig. Absolut perfekt och passade superbra till helheten 😍 Jag kan lätt rekommendera dig för alla bekanta.",
        en:
          "The bridal bouquet was even more beautiful than I'd expected. Absolutely perfect and it suited the whole look so well 😍 I can easily recommend you to everyone I know.",
        name: "Katariina",
        occasion: :wedding,
        lang: "sv"
      },
      %{
        quote:
          "Tack till dej för underbara buketter! Vi var verkligen så nöjda! Och gästerna frågade också varifrån de var! 😉😘 Tack!",
        en:
          "Thank you for the wonderful bouquets! We were so happy! And the guests also asked where they were from! 😉😘 Thank you!",
        name: "Anna",
        lang: "sv"
      }
    ]
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
       review_pages: @review_pages,
       review_page: 0,
       review_leaving: nil,
       review_direction: nil,
       subscribable_products: Catalog.list_subscribable_products!() |> Translations.translate(),
       price_from: price_from(Catalog.list_bouquets!(), locale),
       next_fulfillment: next_fulfillment(locale),
       delivery_fee: delivery_fee(locale)
     )}
  end

  @impl true
  def handle_event("turn_reviews", %{"by" => by}, socket) when by in ["-1", "1"] do
    step = if by == "1", do: 1, else: -1
    leaving = socket.assigns.review_page

    {:noreply,
     assign(socket,
       review_page: Integer.mod(leaving + step, length(@review_pages)),
       review_leaving: leaving,
       review_direction: step
     )}
  end

  defp occasion_label(:wedding), do: ~t"Wedding"
  defp occasion_label(:christening), do: ~t"Christening"

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
        ~t"Free within #{km = km} km for chosen bouquets, otherwise #{base = Format.storefront_price(base, locale)} plus #{per_km = Format.storefront_price(per_km, locale)} per km."

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

      <.trusted_by />

      <section class="overflow-x-clip not-last:border-b" aria-labelledby="reviews-heading">
        <div class="container py-20 md:py-28">
          <div class="mb-12 flex items-baseline justify-between gap-4 md:items-center">
            <h2 id="reviews-heading" class="section-title">{~t"What customers say"}</h2>

            <div class="flex shrink-0 items-center gap-1 md:-mr-1.5">
              <.icon_button
                type="button"
                size="sm"
                class="max-md:hidden"
                phx-click="turn_reviews"
                phx-value-by="-1"
                aria_label={~t"Previous slide"}
                aria-controls="review-pages"
              >
                <.icon name="hero-chevron-left" class="h-5 w-5" />
              </.icon_button>
              <p
                data-review-counter
                data-desktop-counter={"#{@review_page + 1} / #{length(@review_pages)}"}
                class="text-base-content/70 whitespace-nowrap text-sm tabular-nums"
                aria-hidden="true"
              >
                {@review_page + 1} / {length(@review_pages)}
              </p>
              <.icon_button
                type="button"
                size="sm"
                class="max-md:hidden"
                phx-click="turn_reviews"
                phx-value-by="1"
                aria_label={~t"Next slide"}
                aria-controls="review-pages"
              >
                <.icon name="hero-chevron-right" class="h-5 w-5" />
              </.icon_button>
            </div>
          </div>
          <div
            id="review-pages"
            phx-hook=".ReviewsEntrance"
            class="review-pages"
            aria-live="polite"
            data-turned={@review_direction != nil}
            style={@review_direction && "--direction: #{@review_direction};"}
          >
            <div class="review-pages__track">
              <ul
                :for={{page, i} <- Enum.with_index(@review_pages)}
                class="md:grid md:grid-cols-3 md:gap-8"
                data-active={i == @review_page}
                data-leaving={i == @review_leaving}
              >
                <li :for={{review, n} <- Enum.with_index(page)} style={"--n: #{n};"}>
                  <.customer_quote
                    quote={review.quote}
                    lang={review.lang}
                    en={review.en}
                    name={review.name}
                    occasion={review[:occasion] && occasion_label(review.occasion)}
                  />
                </li>
              </ul>
            </div>
          </div>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".ReviewsEntrance">
            import EmblaCarousel from "@/vendor/embla-carousel.esm";

            // On mobile (<md), Embla drives a single-quote carousel with the same focal-point
            // scale/fade as Favourites. On desktop (>=md), Embla is inactive and the first
            // quotes arrive like a turn the first time the section scrolls into view.
            export default {
              mounted() {
                let firstReport = true;
                this.observer = new IntersectionObserver(([entry]) => {
                  if (entry.isIntersecting) {
                    if (!firstReport) this.js().setAttribute(this.el, "data-entering", "");
                    this.observer.disconnect();
                  }
                  firstReport = false;
                });
                this.observer.observe(this.el);

                this.reducedMotion = window.matchMedia(
                  "(prefers-reduced-motion: reduce)",
                ).matches;

                this.embla = EmblaCarousel(this.el, {
                  slides: "li",
                  align: "start",
                  containScroll: "trimSnaps",
                  slidesToScroll: 1,
                  breakpoints: {
                    "(min-width: 768px)": { active: false },
                  },
                });

                this.counterNode = this.el
                  .closest("section")
                  ?.querySelector("[data-review-counter]");
                this.boundOnSelect = this.onSelect.bind(this);
                this.boundOnTween = this.onTween.bind(this);
                this.embla.on("select", this.boundOnSelect);
                this.embla.on("reInit", this.boundOnSelect);
                this.embla.on("reInit", this.boundOnTween);
                this.embla.on("scroll", this.boundOnTween);
                this.embla.on("slideFocus", this.boundOnTween);
                this.onSelect();
                this.onTween();
              },

              updated() {
                if (this.embla) this.embla.reInit();
              },

              destroyed() {
                this.observer.disconnect();
                if (this.embla) this.embla.destroy();
              },

              onSelect() {
                if (!this.counterNode) return;
                if (this.embla.internalEngine().options.active) {
                  this.counterNode.textContent = `${this.embla.selectedScrollSnap() + 1} / ${this.embla.scrollSnapList().length}`;
                } else {
                  this.counterNode.textContent = this.counterNode.dataset.desktopCounter;
                }
              },

              onTween(eventName) {
                if (this.reducedMotion) return;
                const engine = this.embla.internalEngine();
                if (!engine.options.active) return;

                const snapList = this.embla.scrollSnapList();
                const tweenFactor = snapList.length;
                const scrollProgress = this.embla.scrollProgress();
                const slidesInView = this.embla.slidesInView();
                const slideNodes = this.embla.slideNodes();
                const isScrollEvent = eventName === "scroll";

                snapList.forEach((scrollSnap, snapIndex) => {
                  const diffToTarget = scrollSnap - scrollProgress;

                  engine.slideRegistry[snapIndex].forEach((slideIndex) => {
                    if (isScrollEvent && !slidesInView.includes(slideIndex)) return;
                    const progress = Math.min(Math.abs(diffToTarget * tweenFactor), 1);
                    slideNodes[slideIndex].style.setProperty(
                      "--embla-progress",
                      progress.toFixed(3),
                    );
                  });
                });
              },
            };
          </script>
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
            {~t"Fresh flowers every week, every two weeks or every four weeks, delivered or ready to pick up. Pause, change or stop from your account up to #{days = Edenflowers.Orders.Subscription.change_deadline_days()} days before a bouquet."}
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
            src="local:///jennie_6.jpg"
            alt="Jennie"
            width={1500}
            height={1500}
            sizes="(min-width: 768px) 50vw, 100vw"
            class="aspect-[4/5] max-h-[640px] h-full w-full object-cover md:aspect-auto md:h-[640px]"
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
