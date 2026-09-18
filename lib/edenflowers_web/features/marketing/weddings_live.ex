defmodule EdenflowersWeb.Marketing.WeddingsLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @thumb_width 480

  @hero %{src: "local:///wedding/anna_riska_2.jpg", credit: "Anna Riska"}
  @prices_photo %{src: "local:///wedding/eden_flowers_2.jpg", credit: "Eden Flowers"}

  # width/height are the dimensions PhotoSwipe opens the photo at, and the
  # exact size Imgproxy is asked for — the two must agree. Keep each entry's
  # ratio equal to the source photo's so the fill crop is a no-op.
  # Slugs resolve against the Imgproxy local source.
  @gallery [
    %{
      src: "local:///wedding/anna_riska_1.jpg",
      width: 1333,
      height: 2000,
      credit: "Anna Riska"
    },
    %{
      src: "local:///wedding/anna_riska_3.jpg",
      width: 1333,
      height: 2000,
      credit: "Anna Riska"
    },
    %{
      src: "local:///wedding/bjorn_yrjans.jpg",
      width: 1335,
      height: 2000,
      credit: "Björn Yrjans"
    },
    %{
      src: "local:///wedding/daniela_streng_1.jpg",
      width: 1333,
      height: 2000,
      credit: "Daniela Streng"
    },
    %{
      src: "local:///wedding/daniela_streng_2.jpg",
      width: 1333,
      height: 2000,
      credit: "Daniela Streng"
    },
    %{
      src: "local:///wedding/daniela_streng_3.jpg",
      width: 2000,
      height: 1461,
      credit: "Daniela Streng"
    },
    %{
      src: "local:///wedding/daniela_streng_4.jpg",
      width: 1334,
      height: 2000,
      credit: "Daniela Streng"
    },
    %{
      src: "local:///wedding/daniela_streng_5.jpg",
      width: 1333,
      height: 2000,
      credit: "Daniela Streng"
    },
    %{
      src: "local:///wedding/daniela_streng_6.jpg",
      width: 1334,
      height: 2000,
      credit: "Daniela Streng"
    },
    %{
      src: "local:///wedding/eden_flowers_1.jpg",
      width: 1335,
      height: 2000,
      credit: "Eden Flowers"
    },
    # %{src: "local:///wedding/eden_flowers_3.jpg", width: 1500, height: 2000, credit: "Eden Flowers"},
    %{
      src: "local:///wedding/josefin_westin.jpg",
      width: 1400,
      height: 2000,
      credit: "Josefin Westin"
    },
    %{
      src: "local:///wedding/julia_lillqvist.jpg",
      width: 1335,
      height: 2000,
      credit: "Julia Lillqvist"
    },
    %{
      src: "local:///wedding/maria_sundelin.jpg",
      width: 1333,
      height: 2000,
      credit: "Maria Sundelin"
    },
    %{
      src: "local:///wedding/marie_lillhannus.jpg",
      width: 1334,
      height: 2000,
      credit: "Marie Lillhannus"
    },
    %{
      src: "local:///wedding/sara_bjorkskog.jpg",
      width: 1334,
      height: 2000,
      credit: "Sara Björkskog"
    }
  ]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(hero: @hero, prices_photo: @prices_photo, gallery: @gallery, thumb_width: @thumb_width)
     |> assign(prices: prices(), steps: steps(), testimonial: testimonial())}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <section class="from-base-100 to-cream bg-linear-to-b">
        <div class="container pt-28 pb-20 sm:pt-[calc(var(--header-height)+var(--spacing)*12)] md:pb-24">
          <div class="grid items-center gap-10 md:grid-cols-2 md:gap-16">
            <div>
              <h1 class="page-title mb-6 md:text-6xl">{~t"Weddings"}</h1>
              <p class="text-base-content/80 max-w-prose text-lg leading-relaxed">
                {~t"Flowers play an important part in your whole wedding day. I'll help you find the flowers that best match your wishes and reflect who you are as a couple."}
              </p>
              <div class="mt-8 flex flex-wrap items-center gap-6">
                <.button navigate={~p"/contact"} variant="primary">{~t"Request a quote"}</.button>
                <.button href="#my-work" variant="text">{~t"See my work"}</.button>
              </div>
            </div>

            <figure>
              <.image
                src={@hero.src}
                alt={~t"Bride smiling with a colourful bridal bouquet"}
                width={800}
                height={1000}
                sizes="(min-width: 768px) 50vw, 100vw"
                priority
                class="aspect-[4/5] w-full rounded-md object-cover"
              />
              <figcaption class="text-base-content/60 mt-2 text-sm">{photo_credit(@hero.credit)}</figcaption>
            </figure>
          </div>
        </div>
      </section>

      <section :if={@testimonial} class="bg-forest">
        <figure class="container flex flex-col items-center gap-8 py-24 text-center md:py-32">
          <.flower name="flower-30" class="text-forest-content/70 h-12 w-12" />
          <blockquote class="pull-quote text-forest-content max-w-3xl">{@testimonial.quote}</blockquote>
          <figcaption class="eyebrow text-forest-content/70">{@testimonial.couple}</figcaption>
        </figure>
      </section>

      <section aria-labelledby="prices-heading">
        <div class="container grid items-center gap-10 py-24 md:grid-cols-2 md:gap-16">
          <div>
            <h2 id="prices-heading" class="section-title mb-4">{~t"Prices"}</h2>
            <p class="text-base-content/80 mb-8 text-lg leading-relaxed">
              {~t"Every wedding is different, so these are starting prices. You'll get an exact quote once we've talked through your plans."}
            </p>
            <dl class="border-t">
              <div :for={{item, price} <- @prices} class="flex items-baseline justify-between gap-6 border-b py-4">
                <dt class="text-lg">{item}</dt>
                <dd class="text-base-content/80 shrink-0">
                  {starting_price(price)}
                </dd>
              </div>
            </dl>
          </div>

          <figure>
            <.image
              src={@prices_photo.src}
              alt={~t"Wrist corsages of peach roses"}
              width={800}
              height={533}
              sizes="(min-width: 768px) 50vw, 100vw"
              class="aspect-[3/2] w-full rounded-md object-cover"
            />
            <figcaption class="text-base-content/60 mt-2 text-sm">{photo_credit(@prices_photo.credit)}</figcaption>
          </figure>
        </div>
      </section>

      <section class="bg-cream" aria-labelledby="process-heading">
        <div class="container py-24">
          <h2 id="process-heading" class="section-title mb-12">{~t"How it works"}</h2>
          <ol class="grid gap-10 md:grid-cols-4">
            <li :for={{{title, body}, index} <- Enum.with_index(@steps, 1)}>
              <p class="text-primary font-serif text-4xl font-light leading-none">{index}</p>
              <h3 class="card-title mt-6 mb-2">{title}</h3>
              <p class="text-base-content/80 leading-relaxed">{body}</p>
            </li>
          </ol>
        </div>
      </section>

      <section id="my-work" class="scroll-anchor-below-header" aria-labelledby="work-heading">
        <div class="container py-24">
          <h2 id="work-heading" class="section-title mb-10">{~t"My work"}</h2>
          <div
            id="wedding-gallery"
            phx-hook="PhotoGallery"
            class="columns-2 gap-2 md:columns-3 xl:columns-4"
          >
            <figure :for={{photo, index} <- Enum.with_index(@gallery)} class="mb-2 break-inside-avoid">
              <a
                href={image_url(photo.src, photo.width, photo.height)}
                data-pswp-width={photo.width}
                data-pswp-height={photo.height}
                data-pswp-credit={photo.credit && photo_credit(photo.credit)}
                target="_blank"
                rel="noreferrer"
                class="block"
              >
                <.image
                  src={photo.src}
                  alt={~t"Wedding flowers"}
                  width={@thumb_width}
                  height={thumb_height(photo)}
                  quality={80}
                  sizes="(min-width: 96rem) calc(90.5rem / 4), (min-width: 80rem) calc(74.5rem / 4), (min-width: 64rem) calc(59rem / 3), (min-width: 48rem) calc(43rem / 3), (min-width: 40rem) 17.75rem, calc((100vw - 2.5rem) / 2)"
                  class="w-full rounded-md"
                />
              </a>
            </figure>
          </div>
        </div>
      </section>

      <section class="bg-forest">
        <div class="container flex flex-col items-center gap-8 py-24 text-center md:py-32">
          <p class="section-title text-forest-content">{~t"Planning a wedding?"}</p>
          <.button navigate={~p"/contact"} variant="inverse">{~t"Request a quote"}</.button>
        </div>
      </section>
    </Layouts.app>
    """
  end

  # Starting prices in euros; nil renders as "On request".
  defp prices do
    [
      {~t"Bridal bouquet", nil},
      {~t"Bridesmaids' bouquets", nil},
      {~t"Flower girl bouquets", nil},
      {~t"Corsages", nil},
      {~t"Flower crowns and floral jewellery", nil},
      {~t"Ceremony and reception decoration", nil}
    ]
  end

  defp steps do
    [
      {~t"Get in touch", ~t"Tell me your date, venue and a little about the day you're imagining."},
      {~t"Consultation", ~t"We meet to talk through colours, flowers and style, in the shop or online."},
      {~t"Design and quote", ~t"I put together a proposal and a quote. Once you're happy, your date is booked."},
      {~t"The wedding day", ~t"Your flowers are made fresh and delivered, and I can decorate the venue on site."}
    ]
  end

  defp starting_price(nil), do: ~t"On request"

  defp starting_price(euros) do
    amount = Edenflowers.Format.currency(euros, Edenflowers.Format.locale())
    ~t"from #{amount}"
  end

  # Returns %{quote: ..., couple: ...} once there's a testimonial to show.
  defp testimonial, do: nil

  defp photo_credit(credit), do: ~t"Photo: #{credit}"

  defp thumb_height(photo), do: round(@thumb_width * photo.height / photo.width)
end
