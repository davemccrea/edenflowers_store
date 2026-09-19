defmodule EdenflowersWeb.Marketing.WeddingsLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @thumb_width 480

  # Photographers without a known website are credited by name only.
  @photographer_sites %{
    "Björn Yrjans" => "https://www.bjornyrjans.com/",
    "Daniela Streng" => "https://www.danielastreng.com/",
    "Josefin Westin" => "https://www.josefinwestin.com/",
    "Julia Lillqvist" => "https://julialillqvist.com/",
    "Maria Sundelin" => "https://www.instagram.com/mariatheresesphotography/",
    "Marie Lillhannus" => "https://www.picmi.fi/",
    "Sara Björkskog" => "https://www.grann.fi/"
  }

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(gallery: gallery(), thumb_width: @thumb_width, enquiry_mailto: enquiry_mailto())
     |> assign(prices: prices(), steps: steps(), testimonial: testimonial())}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <section class="flex items-center not-last:border-b md:min-h-dvh">
        <div class="container pt-28 pb-20 sm:pt-(--header-clearance) md:pb-16">
          <div class="grid items-center gap-10 md:grid-cols-2 md:gap-16">
            <div>
              <h1 class="page-title mb-6">{~t"Weddings"}</h1>
              <p class="text-base-content/80 max-w-prose text-lg leading-relaxed">
                {~t"Flowers play an important part in your whole wedding day. I'll help you find the flowers that best match your wishes and reflect who you are as a couple."}
              </p>
              <div class="mt-8 flex flex-wrap items-center gap-6">
                <.button href="#enquire" variant="primary">{~t"Request a quote"}</.button>
                <.button href="#my-work" variant="text">{~t"See my work"}</.button>
              </div>
            </div>

            <%!-- On desktop the photo's height is capped so the whole section fits one screen. --%>
            <figure class="md:justify-self-end">
              <.image
                src="local:///wedding/anna_riska_2.jpg"
                alt={~t"Bride smiling with a colourful bridal bouquet"}
                width={800}
                height={1000}
                sizes="(min-width: 768px) 50vw, 100vw"
                priority
                class="aspect-[4/5] w-full object-cover object-top md:max-h-[calc(100dvh-var(--header-clearance)-6rem)] md:w-auto"
              />
              <figcaption class="text-base-content/70 mt-2 text-sm"><.credit_line name="Anna Riska" /></figcaption>
            </figure>
          </div>
        </div>
      </section>

      <section id="my-work" class="scroll-anchor-below-header not-last:border-b" aria-labelledby="work-heading">
        <div class="container py-24">
          <h2 id="work-heading" class="section-title mb-10">{~t"My work"}</h2>
          <div
            id="wedding-gallery"
            phx-hook="PhotoGallery"
            class="columns-2 gap-3 md:columns-3 xl:columns-4"
          >
            <figure :for={photo <- @gallery} class="mb-6 break-inside-avoid">
              <a
                href={image_url(photo.src, photo.width, photo.height)}
                data-pswp-width={photo.width}
                data-pswp-height={photo.height}
                target="_blank"
                rel="noreferrer"
                class="block"
              >
                <.image
                  src={photo.src}
                  alt={photo.alt}
                  width={@thumb_width}
                  height={thumb_height(photo)}
                  quality={80}
                  sizes="(min-width: 96rem) calc(90.5rem / 4), (min-width: 80rem) calc(74.5rem / 4), (min-width: 64rem) calc(59rem / 3), (min-width: 48rem) calc(43rem / 3), (min-width: 40rem) 17.75rem, calc((100vw - 2.5rem) / 2)"
                  class="w-full"
                />
              </a>
              <figcaption class="text-base-content/70 mt-1.5 text-xs"><.credit_line name={photo.credit} /></figcaption>
            </figure>
          </div>
        </div>
      </section>

      <section :if={@testimonial} class="bg-forest not-last:border-b">
        <figure class="container flex flex-col items-center gap-8 py-24 text-center md:py-32">
          <.flower name="flower-30" class="text-forest-content/70 h-12 w-12" />
          <blockquote class="pull-quote text-forest-content max-w-3xl">{@testimonial.quote}</blockquote>
          <figcaption class="eyebrow text-forest-content/70">{@testimonial.couple}</figcaption>
        </figure>
      </section>

      <section class="not-last:border-b" aria-labelledby="prices-heading">
        <div class="container grid items-center gap-10 py-24 md:grid-cols-2 md:gap-16">
          <div>
            <h2 id="prices-heading" class="section-title mb-4">{~t"Prices"}</h2>
            <p class="text-base-content/80 mb-8 text-lg leading-relaxed">
              {~t"Every wedding is different, so these are starting prices. You'll get an exact quote once we've talked through your plans."}
            </p>
            <dl class="border-t">
              <div :for={{item, price} <- @prices} class="flex items-baseline justify-between gap-6 border-b py-4">
                <dt class="text-lg">{item}</dt>
                <dd class="text-base-content/80 shrink-0 tabular-nums">
                  {starting_price(price)}
                </dd>
              </div>
            </dl>
          </div>

          <figure>
            <.image
              src="local:///wedding/eden_flowers_2.jpg"
              alt={~t"Wrist corsages of peach roses"}
              width={800}
              height={533}
              sizes="(min-width: 768px) 50vw, 100vw"
              class="aspect-[3/2] w-full object-cover"
            />
            <figcaption class="text-base-content/70 mt-2 text-sm"><.credit_line name="Eden Flowers" /></figcaption>
          </figure>
        </div>
      </section>

      <section class="not-last:border-b" aria-labelledby="process-heading">
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

      <section
        id="enquire"
        class="bg-forest scroll-anchor-below-header not-last:border-b"
        aria-labelledby="enquire-heading"
      >
        <div class="grid md:grid-cols-2">
          <.image
            src="local:///jennie_99.jpg"
            alt="Jennie"
            width={1080}
            height={1350}
            sizes="(min-width: 768px) 50vw, 100vw"
            class="aspect-[4/5] max-h-[640px] h-full w-full object-cover md:aspect-auto"
          />

          <div class="flex flex-col items-start gap-8 px-4 py-20 sm:px-8 md:justify-center md:px-12 lg:px-20">
            <.flower name="flower-30" class="text-forest-content/70 h-12 w-12" />
            <h2 id="enquire-heading" class="section-title text-forest-content">{~t"Planning a wedding?"}</h2>
            <p class="text-forest-content/85 max-w-prose text-lg leading-relaxed">
              {~t"I'm Jennie, and I design every wedding myself, from our first conversation to the flowers on the day. Email me your date, your venue and roughly how many guests you're expecting. If there are photos here you love, mention those too."}
            </p>
            <.button href={@enquiry_mailto} variant="inverse">{~t"Email me about your wedding"}</.button>
            <p class="text-forest-content/85">
              {~t"Or call me on"}
              <a href="tel:+358402209494" class="link-underline-static-body whitespace-nowrap">040 220 9494</a>
            </p>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  # width/height are the dimensions PhotoSwipe opens the photo at, and the
  # exact size Imgproxy is asked for — the two must agree. Keep each entry's
  # ratio equal to the source photo's so the fill crop is a no-op.
  # Ordered by strength, not by photographer.
  defp gallery do
    [
      %{
        src: "local:///wedding/anna_riska_3.jpg",
        width: 1333,
        height: 2000,
        credit: "Anna Riska",
        alt: ~t"Couple embracing, the bride holding a white bouquet"
      },
      %{
        src: "local:///wedding/julia_lillqvist.jpg",
        width: 1335,
        height: 2000,
        credit: "Julia Lillqvist",
        alt: ~t"Bouquet of burgundy protea, pink roses and dahlias"
      },
      %{
        src: "local:///wedding/daniela_streng_5.jpg",
        width: 1333,
        height: 2000,
        credit: "Daniela Streng",
        alt: ~t"Bride seen from behind, holding a meadow bouquet"
      },
      %{
        src: "local:///wedding/eden_flowers_1.jpg",
        width: 1335,
        height: 2000,
        credit: "Eden Flowers",
        alt: ~t"Bride and two bridesmaids holding white bouquets"
      },
      %{
        src: "local:///wedding/josefin_westin.jpg",
        width: 1400,
        height: 2000,
        credit: "Josefin Westin",
        alt: ~t"Bride outdoors with a bright blue and red bouquet"
      },
      %{
        src: "local:///wedding/daniela_streng_2.jpg",
        width: 1333,
        height: 2000,
        credit: "Daniela Streng",
        alt: ~t"Bride holding a white and green bouquet"
      },
      %{
        src: "local:///wedding/maria_sundelin.jpg",
        width: 1333,
        height: 2000,
        credit: "Maria Sundelin",
        alt: ~t"Deep red and blush bouquet against a white dress"
      },
      %{
        src: "local:///wedding/daniela_streng_4.jpg",
        width: 1334,
        height: 2000,
        credit: "Daniela Streng",
        alt: ~t"Bride in a forest clearing with a pastel bouquet"
      },
      %{
        src: "local:///wedding/sara_bjorkskog.jpg",
        width: 1334,
        height: 2000,
        credit: "Sara Björkskog",
        alt: ~t"Close-up of a bouquet with white cosmos"
      },
      %{
        src: "local:///wedding/bjorn_yrjans.jpg",
        width: 1335,
        height: 2000,
        credit: "Björn Yrjans",
        alt: ~t"Couple kissing beside a trailing white bouquet"
      },
      %{
        src: "local:///wedding/daniela_streng_6.jpg",
        width: 1334,
        height: 2000,
        credit: "Daniela Streng",
        alt: ~t"Peach, orange and white bouquet against a lace dress"
      },
      %{
        src: "local:///wedding/marie_lillhannus.jpg",
        width: 1334,
        height: 2000,
        credit: "Marie Lillhannus",
        alt: ~t"White and rust bouquet held low at the bride's side"
      },
      %{
        src: "local:///wedding/daniela_streng_1.jpg",
        width: 1333,
        height: 2000,
        credit: "Daniela Streng",
        alt: ~t"Bouquet held up against a blue summer sky"
      },
      %{
        src: "local:///wedding/daniela_streng_3.jpg",
        width: 2000,
        height: 1461,
        credit: "Daniela Streng",
        alt: ~t"Bouquet of roses and greenery on a wooden jetty"
      },
      %{
        src: "local:///wedding/anna_riska_1.jpg",
        width: 1333,
        height: 2000,
        credit: "Anna Riska",
        alt: ~t"Blue hydrangea in a glass vase beside bridal shoes"
      }
    ]
  end

  # Starting prices in euros; nil renders as "On request".
  # Placeholders until Jennie confirms her real figures.
  defp prices do
    [
      {~t"Bridal bouquet", 150},
      {~t"Bridesmaids' bouquets", 70},
      {~t"Flower girl bouquets", 40},
      {~t"Corsages", 25},
      {~t"Flower crowns and floral jewellery", 60},
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

  # mailto doesn't decode "+" as a space, so encode everything but unreserved characters.
  defp enquiry_mailto do
    subject = URI.encode(~t"Wedding enquiry", &URI.char_unreserved?/1)

    body =
      [~t"Wedding date:", ~t"Venue:", ~t"Number of guests:", ~t"Colours and flowers we like:"]
      |> Enum.map_join("\n", &(&1 <> " "))
      |> URI.encode(&URI.char_unreserved?/1)

    "mailto:info@edenflowers.fi?subject=#{subject}&body=#{body}"
  end

  defp starting_price(nil), do: ~t"On request"

  defp starting_price(euros) do
    amount =
      Localize.Number.to_string!(euros,
        locale: Edenflowers.Format.locale(),
        currency: :EUR,
        fractional_digits: 0
      )

    ~t"from #{amount}"
  end

  # Returns %{quote: ..., couple: ...} once there's a testimonial to show.
  defp testimonial, do: nil

  attr :name, :string, required: true

  defp credit_line(assigns) do
    assigns = assign(assigns, :url, @photographer_sites[assigns.name])

    ~H"""
    {~t"Photo:"}
    <a :if={@url} href={@url} target="_blank" rel="noopener noreferrer" class="link-underline-static-body">
      {@name}
    </a>
    <span :if={!@url}>{@name}</span>
    """
  end

  defp thumb_height(photo), do: round(@thumb_width * photo.height / photo.width)
end
