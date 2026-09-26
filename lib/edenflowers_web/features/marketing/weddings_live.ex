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
     |> assign(personal_flowers: personal_flowers(), decorations: decorations(), decoration_photos: decoration_photos(), example_weddings: example_weddings())
     |> assign(steps: steps(), testimonial: testimonial())}
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

      <section id="my-work" class="bg-cream scroll-anchor-below-header not-last:border-b" aria-labelledby="work-heading">
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
              <figcaption class="text-cream-content/80 mt-1.5 text-xs"><.credit_line name={photo.credit} /></figcaption>
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
        <div class="container py-24">
          <div class="grid items-start gap-10 md:grid-cols-2 md:gap-16">
            <div>
              <h2 id="prices-heading" class="section-title mb-4">{~t"Prices"}</h2>
              <p class="text-base-content/80 mb-10 text-lg leading-relaxed">
                {~t"Every wedding is different, so you'll get an exact quote once we've talked through your plans. Final prices depend on the flowers and techniques you choose."}
              </p>
              <h3 class="tile-title mb-3">{~t"Bouquets and accessories"}</h3>
              <.price_list items={@personal_flowers} />
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

          <div class="border-base-content/12 mt-20 grid gap-10 border-t pt-16 md:grid-cols-2 md:gap-16">
            <div>
              <h3 class="tile-title mb-3">{~t"Decoration"}</h3>
              <.price_list items={@decorations} />
            </div>
          </div>

          <div class="mt-10 grid grid-cols-2 gap-3 md:grid-cols-4 md:gap-6">
            <figure :for={photo <- @decoration_photos}>
              <.image
                src={photo.src}
                alt={photo.alt}
                width={600}
                height={800}
                sizes="(min-width: 48rem) 25vw, 50vw"
                class="aspect-[3/4] w-full object-cover"
              />
              <figcaption class="mt-2">{photo.caption}</figcaption>
            </figure>
          </div>

          <div class="border-base-content/12 mt-20 border-t pt-16">
            <h3 class="tile-title text-balance mb-4">{~t"Example weddings"}</h3>
            <p class="text-base-content/80 mb-8 max-w-prose text-lg leading-relaxed">
              {~t"What a whole wedding typically costs. Your quote is built from the prices above, so add or leave out whatever you like."}
            </p>
            <div class="grid gap-4 md:grid-cols-3 md:gap-6">
              <article :for={wedding <- @example_weddings} class="bg-cream text-cream-content p-6 sm:p-8">
                <header class="flex items-baseline justify-between gap-4">
                  <h4 class="font-serif text-2xl">{wedding.name}</h4>
                  <p class="font-serif shrink-0 text-lg tabular-nums">{price_label({:from, wedding.from})}</p>
                </header>
                <p class="text-cream-content/70 mt-1 text-sm">{wedding.guests}</p>
                <ul class="text-cream-content/85 mt-4 list-disc space-y-1.5 pl-5">
                  <li :for={item <- wedding.items}>{item}</li>
                </ul>
              </article>
            </div>
            <p class="text-base-content/70 mt-10 text-sm">
              {~t"Delivery costs are added outside Vaasa."}
            </p>
          </div>
        </div>
      </section>

      <section class="not-last:border-b" aria-labelledby="process-heading">
        <div class="container py-24">
          <h2 id="process-heading" class="section-title mb-12">{~t"How it works"}</h2>
          <ol class="grid gap-10 md:grid-cols-3">
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

  # Prices in euros, from Jennie's 2027 wedding price list.
  defp personal_flowers do
    [
      {~t"Bridal bouquet", {:range, 110, 190}},
      {~t"Bridesmaid's bouquet", {:from, 45}},
      {~t"Flower girl or toss bouquet", {:from, 35}},
      {~t"Corsage or pocket square", {:from, 19}},
      {~t"Hair and wrist flowers (crown, clip, tiara, bracelet)", {:from, 32}},
      {~t"Cake flowers", :on_request}
    ]
  end

  defp decorations do
    [
      {~t"Silk flower garland, to rent", {:fixed, 95}},
      {~t"Flower arch or flower gate", {:from, 320}},
      {~t"Arrangement in an urn or on a pedestal", {:from, 95}},
      {~t"Welcome sign arrangement", {:from, 70}}
    ]
  end

  # All four photos are 3:4, so the 600x800 fill crop is a no-op.
  defp decoration_photos do
    [
      %{
        src: "local:///wedding/eden_flowers_arch.jpg",
        caption: ~t"Flower arch",
        alt: ~t"Round gold flower arch with white and peach roses"
      },
      %{
        src: "local:///wedding/eden_flowers_gate.jpg",
        caption: ~t"Flower gate",
        alt: ~t"Wooden flower gate with white drapes and summer flowers"
      },
      %{
        src: "local:///wedding/eden_flowers_garland.jpg",
        caption: ~t"Silk flower garland, to rent",
        alt: ~t"Silk flower garland cascading down a cake table"
      },
      %{
        src: "local:///wedding/eden_flowers_urns.jpg",
        caption: ~t"Arrangement in an urn or on a pedestal",
        alt: ~t"Two urn arrangements of coral roses and delphiniums"
      }
    ]
  end

  # Totals are the sum of the price list items, rounded up to the nearest 5 euros.
  # Table flowers are priced as the old Basic package (€250) and Classic's table
  # and venue flowers as the old Medium package (€350).
  defp example_weddings do
    bridal_flowers = [
      ~t"Bridal bouquet",
      ~t"Two bridesmaids' bouquets",
      ~t"Four corsages or pocket squares"
    ]

    [
      %{
        name: ~t"Small and simple",
        guests: ~t"About 40 guests",
        from: 265,
        items: [
          ~t"Bridal bouquet",
          ~t"Bridesmaid's bouquet",
          ~t"Two corsages or pocket squares",
          ~t"Welcome sign arrangement"
        ]
      },
      %{
        name: ~t"Classic",
        guests: ~t"About 100 guests",
        from: 630,
        items:
          bridal_flowers ++
            [
              ~t"Flowers in vases on every table",
              ~t"Two arrangements for the ceremony or reception",
              ~t"Consultation, delivery and set-up"
            ]
      },
      %{
        name: ~t"Full styling",
        guests: ~t"About 100 guests",
        from: 1040,
        items:
          bridal_flowers ++
            [
              ~t"Flowers in vases on every table",
              ~t"Flower arch",
              ~t"Two large arrangements in urns or on pedestals",
              ~t"Consultation, delivery and set-up"
            ]
      }
    ]
  end

  defp steps do
    [
      {~t"Get in touch",
       ~t"Get in touch and tell me your date and a little about what you're looking for. It's best to reach out well in advance."},
      {~t"Quote", ~t"I'll send you my quote, and you can come back to me with any questions and confirm your booking."},
      {~t"Consultation",
       ~t"If you'd like, we meet 1–2 months before the wedding to go through what you need. I want you to feel completely confident that the flowers will turn out exactly as you imagined."},
      {~t"Payment",
       ~t"Half is invoiced as a booking fee about 4 weeks before the wedding, and the rest afterwards. The booking fee isn't refunded if you cancel later than four weeks before the wedding."},
      {~t"The wedding day",
       ~t"Your flowers are collected or delivered, whichever you prefer. If you've chosen decoration, I come to your venue and decorate it with the flowers we've agreed on."}
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

  attr :items, :list, required: true

  defp price_list(assigns) do
    ~H"""
    <dl class="border-t">
      <div :for={{item, price} <- @items} class="flex items-baseline justify-between gap-6 border-b py-3">
        <dt class="text-lg">{item}</dt>
        <dd class="text-base-content font-serif shrink-0 text-lg tabular-nums">{price_label(price)}</dd>
      </div>
    </dl>
    """
  end

  defp price_label(:on_request), do: ~t"On request"
  defp price_label({:fixed, euros}), do: euros(euros)
  defp price_label({:range, low, high}), do: "#{euros(low)}–#{euros(high)}"

  defp price_label({:from, low}) do
    amount = euros(low)
    ~t"from #{amount}"
  end

  defp euros(amount), do: Edenflowers.Format.price(amount, Edenflowers.Format.locale())

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
