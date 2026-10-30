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
    products =
      Catalog.list_featured_products!()
      |> Translations.translate()
      |> Translations.translate_assoc(:product_category)

    locale = Format.locale()
    free_dist_km = Fulfillment.free_dist_km()

    {:ok,
     assign(socket,
       page_title: ~t"Florist in Vaasa",
       alternates: alternates("/#{language}"),
       page_description: page_description(free_dist_km),
       json_ld: [EdenflowersWeb.Business.website(), EdenflowersWeb.Business.florist()],
       products: products,
       free_dist_km: free_dist_km,
       review_pages: @review_pages,
       review_page: 0,
       review_leaving: nil,
       review_direction: nil,
       subscribable_products: Catalog.list_subscribable_products!() |> Translations.translate(),
       price_from: price_from(Catalog.list_bouquets!(), locale),
       cards: Catalog.list_large_cards!() |> Translations.translate(),
       card_price_from: card_price_from(Catalog.list_card_drawer_variants!(), locale),
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

  defp card_price_from([], _locale), do: nil

  defp card_price_from(variants, locale) do
    variants |> Enum.map(& &1.price) |> Enum.min(Decimal) |> Format.storefront_price(locale)
  end

  defp page_description(nil) do
    ~t"Fresh flowers by Jennie at Eden Flowers in Vaasa: bouquets, flower subscriptions, wedding and funeral flowers."
  end

  defp page_description(km) do
    gettext_comment("%{km} is the configured free-delivery distance in kilometres; only selected bouquets qualify.")

    ~t"Fresh flowers by Jennie at Eden Flowers in Vaasa: bouquets, flower subscriptions, wedding and funeral flowers. Free delivery within #{km = km} km of Minimossen on selected bouquets."
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
      notice_bar={@notice_bar}
      alternates={@alternates}
    >
      <section id="home-hero" phx-hook=".HomeHero" data-header-overlay class="relative overflow-hidden not-last:border-b">
        <%!-- Phones get the photo's own 2:3 portrait so the box crops it only once --%>
        <.image
          src="local:///wedding/daniela_streng_1.jpg"
          alt=""
          width={1920}
          height={1080}
          sources={[%{media: "(max-width: 767px)", width: 960, height: 1440, max_width: 960}]}
          quality={60}
          priority
          class="hero-zoom h-[90svh] w-full object-cover md:h-dvh"
        />
        <div class="pointer-events-none absolute inset-0 opacity-60 mix-blend-soft-light bg-(image:--grain)"></div>
        <div class="container absolute inset-0 flex flex-col justify-end pb-16 sm:pb-28 md:pb-20">
          <h1 class="hero-display hero-focus max-w-[16ch] text-white" style="--reveal-delay: 80ms;">
            <span class="sr-only">{~t"Flowers for every stage of life"}</span>
            <span aria-hidden="true">
              {~t"Flowers for"}
              <span class="hero-rotator italic">
                <span style="--i: 0;">{~t"every stage of life"}</span>
                <span style="--i: 1;">{~t"a new arrival"}</span>
                <span style="--i: 2;">{~t"your wedding day"}</span>
                <span style="--i: 3;">{~t"a cosy weekend"}</span>
                <span style="--i: 4;">{~t"every stage of life"}</span>
              </span>
            </span>
          </h1>
          <p
            class="hero-reveal text-balance mt-6 max-w-md text-lg leading-relaxed text-white"
            style="--reveal-delay: 600ms;"
          >
            <%= if @price_from do %>
              {~t"Bouquets made fresh on delivery day, from #{price = @price_from}."}
            <% else %>
              {~t"Bouquets made fresh on delivery day."}
            <% end %>
          </p>
          <div class="hero-reveal mt-10" style="--reveal-delay: 750ms;">
            <.button
              navigate={~q"/#{language}/store"}
              variant="light"
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
      <script :type={Phoenix.LiveView.ColocatedHook} name=".HomeHero">
        // The hero animates once a session. The root layout's head script covers reloads,
        // and leaving marks <html> so live navigation back here doesn't replay it either.
        export default {
          mounted() {
            try {
              sessionStorage.setItem("hero-seen", "1");
            } catch {}
          },
          destroyed() {
            document.documentElement.classList.add("hero-seen");
          },
        };
      </script>

      <section :if={@products != []} id="store" class="not-last:border-b">
        <div class="container py-16 md:py-24 xl:max-w-[70vw]">
          <div class="mb-4 flex items-end justify-between gap-4 px-2">
            <div>
              <h2 class="section-title">
                {if Enum.all?(@products, &(&1.product_category.slug == "bouquets")),
                  do: ~t"Favourite bouquets",
                  else: ~t"Favourites"}
              </h2>
              <.free_delivery_note
                :if={@free_dist_km && Enum.any?(@products, & &1.free_delivery)}
                free_dist_km={@free_dist_km}
                class="mt-2"
              />
            </div>

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
                    category={product.product_category.name}
                    navigate={~q"/#{language}/product/#{product}"}
                    locale={Edenflowers.Format.locale()}
                    free_dist_km={@free_dist_km}
                  />
                </div>
              </div>
            </div>
            <script :type={Phoenix.LiveView.ColocatedHook} name=".FeaturedCarousel">
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
                  // Fetched here rather than imported so only the home page downloads it.
                  import("@/vendor/embla-carousel.esm").then(({ default: EmblaCarousel }) => {
                    if (this.el.isConnected) this.setup(EmblaCarousel);
                  });
                },

                setup(EmblaCarousel) {
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

            <div class="embla__dots mt-4 hidden justify-center gap-2 sm:flex md:hidden" />
          </div>

          <div class="mt-10 text-center">
            <.link navigate={~q"/#{language}/store"} class="eyebrow link-underline-hover touch-target">
              {~t"Shop all flowers"}
            </.link>
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
            quality={70}
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
              class="eyebrow text-forest-content link-underline-hover touch-target group inline-flex items-center gap-2"
            >
              {~t"Meet Jennie"}
              <.icon
                name="hero-arrow-right"
                class="h-4 w-4 transition-transform duration-300 ease-out group-hover:translate-x-1"
              />
            </.link>
          </div>
        </div>
      </section>

      <section class="overflow-x-clip not-last:border-b" aria-labelledby="reviews-heading">
        <div class="container py-20 md:py-28">
          <.flower
            name="flower-30"
            class="text-base-content/20 [--flower-spin-turn:4deg] -mb-4 -ml-4 h-16 w-16 md:-mb-5 md:h-20 md:w-20"
          />
          <div class="relative mb-12 flex items-baseline justify-between gap-4 md:items-center">
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
            // On mobile (<md), Embla drives a single-quote carousel with the same focal-point
            // scale as Favourites. On desktop (>=md), Embla is inactive and the first
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

                // Fetched here rather than imported so only the home page downloads it.
                import("@/vendor/embla-carousel.esm").then(({ default: EmblaCarousel }) => {
                  if (this.el.isConnected) this.setup(EmblaCarousel);
                });
              },

              setup(EmblaCarousel) {
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

      <.trusted_by />

      <section
        :if={@subscribable_products != []}
        id="subscription"
        class="bg-cream not-last:border-b"
        aria-labelledby="subscription-heading"
      >
        <div :for={product <- @subscribable_products} :if={length(@subscribable_products) == 1} class="grid md:grid-cols-2">
          <div class="bg-cream">
            <.image
              src="local:///subscription.jpg"
              alt=""
              width={1200}
              height={1200}
              sizes="(min-width: 768px) 50vw, 100vw"
              class="aspect-[4/5] h-full w-full object-cover md:aspect-square"
            />
          </div>
          <div class="flex flex-col px-4 py-16 sm:px-8 md:justify-center md:px-12 md:py-20 lg:px-20">
            <h2 id="subscription-heading" class="section-title mb-6">{~t"Flower subscription"}</h2>
            <p class="eyebrow text-base-content/70 mb-4">
              {product.name} · {~t"From"} {Edenflowers.Format.storefront_price(
                product.cheapest_price,
                Edenflowers.Format.locale()
              )}
            </p>
            <p class="text-base-content/80 mb-10 max-w-prose text-lg leading-relaxed">
              {~t"Flowers for you or someone else every week, every two weeks or every four weeks, delivered or ready to pick up. Pause, change or stop from your account up to #{days = Edenflowers.Orders.Subscription.change_deadline_days()} days before a bouquet."}
            </p>
            <.button
              navigate={~q"/#{language}/product/#{product}?subscribe=1"}
              variant="primary"
              class="group w-fit"
            >
              {~t"Start a subscription"}
              <.icon
                name="hero-arrow-right-mini"
                class="h-4 w-4 transition-transform duration-300 ease-out group-hover:translate-x-1"
              />
            </.button>
          </div>
        </div>
        <div :if={length(@subscribable_products) > 1} class="container py-20 md:py-28">
          <h2 id="subscription-heading" class="section-title mb-6">{~t"Flower subscription"}</h2>
          <p class="text-base-content/80 mb-12 max-w-prose text-lg leading-relaxed">
            {~t"Flowers for you or someone else every week, every two weeks or every four weeks, delivered or ready to pick up. Pause, change or stop from your account up to #{days = Edenflowers.Orders.Subscription.change_deadline_days()} days before a bouquet."}
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

      <section :if={@cards != []} id="cards" class="overflow-x-clip not-last:border-b" aria-labelledby="cards-heading">
        <div class="container grid items-center gap-12 py-20 md:py-28 lg:grid-cols-2">
          <ul
            id="card-fan"
            phx-hook=".CardFan"
            class="card-fan lg:order-last"
            style={"--n: #{length(@cards)};"}
            aria-label={~t"Cards"}
          >
            <li :for={{card, i} <- Enum.with_index(@cards)} style={"--i: #{i};"}>
              <%!-- Card artwork is fine line work, which looks soft at the default WebP quality. --%>
              <.image
                src={card.main_photo_slug}
                alt={card.name}
                width={487}
                height={611}
                crop_type="fit"
                quality={90}
                sizes="(min-width: 768px) 13rem, 9.5rem"
              />
            </li>
          </ul>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".CardFan">
            export default {
              mounted() {
                this.observer = new IntersectionObserver(
                  ([entry]) => {
                    if (entry.isIntersecting) {
                      this.js().setAttribute(this.el, "data-open", "");
                      this.observer.disconnect();
                    }
                  },
                  { threshold: 0.6 },
                );
                this.observer.observe(this.el);
              },

              destroyed() {
                this.observer.disconnect();
              },
            };
          </script>

          <div class="flex flex-col items-start">
            <h2 id="cards-heading" class="section-title mb-6">{~t"A card in Jennie's hand"}</h2>
            <p :if={@card_price_from} class="eyebrow text-base-content/70 mb-4">
              {~t"Cards from #{price = @card_price_from}"}
            </p>
            <p class="text-base-content/80 mb-4 max-w-prose text-lg leading-relaxed">
              {~t"Add a card to your bouquet at checkout and tell us what it should say. Jennie writes your message by hand and tucks it in with the flowers."}
            </p>
            <p class="text-base-content/70 mb-10 text-sm">
              {~t"Illustrated by"}
              <a
                href="https://cardsbyjojo.se/"
                target="_blank"
                rel="noopener noreferrer"
                class="link-underline-hover hover:text-base-content"
              >
                Cards by Jojo
              </a>
            </p>
            <.button navigate={~q"/#{language}/store"} variant="primary" class="group w-fit">
              {~t"Choose bouquet"}
              <.icon
                name="hero-arrow-right-mini"
                class="h-4 w-4 transition-transform duration-300 ease-out group-hover:translate-x-1"
              />
            </.button>
          </div>
        </div>
      </section>

      <section class="not-last:border-b" aria-labelledby="location-heading">
        <div class="grid md:grid-cols-2">
          <div class="flex flex-col px-4 pt-8 pb-16 sm:px-8 md:justify-center md:px-12 md:py-32 lg:px-20">
            <.flower
              name="flower-41"
              class="text-base-content/20 [--flower-spin-turn:4deg] -mb-4 -ml-4 h-16 w-16 md:-mb-5 md:h-20 md:w-20"
            />
            <h2 id="location-heading" class="section-title relative mb-8">{~t"Delivery and pickup"}</h2>
            <p :if={@notice_bar} id="location-order-status" class="mb-6 max-w-prose text-lg font-semibold leading-relaxed">
              {@notice_bar}
            </p>
            <dl class="grid max-w-prose gap-6 text-lg leading-relaxed">
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

          <%!-- On desktop the map fills the text column's height instead of setting its own --%>
          <div class="order-first md:relative md:order-none">
            <.image
              src="local:///home-vaasa-map-3.png"
              alt={~t"Map of Vaasa, Finland with Minimossen pinned"}
              width={1600}
              height={1880}
              sizes="(min-width: 768px) 50vw, 100vw"
              quality={95}
              class="aspect-[4/3] max-h-80 w-full object-cover md:aspect-auto md:max-h-none md:absolute md:inset-0 md:h-full"
            />
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
