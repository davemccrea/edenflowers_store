defmodule EdenflowersWeb.Marketing.AboutLive do
  @moduledoc """
  Public about page: Jennie's story, her style and how she works.
  """

  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Marketing.CustomerQuote
  import EdenflowersWeb.Marketing.TrustedBy

  alias EdenflowersWeb.Business
  alias EdenflowersWeb.Marketing.ContactDrawer

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: ~t"About me",
       alternates: alternates("/#{language}/about"),
       page_description:
         ~t"Meet Jennie, the florist behind Eden Flowers in Vaasa: warm, natural bouquets with seasonal flowers that last, made by her from the first message to the finished flowers.",
       og_image: image_url("local:///jennie_1.jpg", 1200, 630),
       json_ld: Business.florist(),
       quotes: quotes()
     )}
  end

  # Kept in the customer's own words. `en` is shown beneath the original on /en only.
  defp quotes do
    [
      %{
        text: "Det är en underbar underbar skapelse som du har gjort. … Verkligen, jag gillar så mycket din stil.",
        lang: "sv",
        en: "It's a wonderful, wonderful creation you've made. … Truly, I like your style so much.",
        name: "Triinu",
        occasion: nil
      },
      %{
        text:
          "Var så smidigt att du kunde ta dej dit under dagen och fixa i lugn och ro och jag kände aldrig någon stress över att blommorna inte skulle vara perfekta under dagen.",
        lang: "sv",
        en:
          "It was so easy that you could go there during the day and set everything up in peace, and I never felt any stress about the flowers not being perfect on the day.",
        name: "Julia",
        occasion: ~t"Wedding"
      },
      %{
        text:
          "Teit meille kukat häihimme pari vuotta sitten, joten oli ihana saada kukat sinulta myös tyttäremme ensimmäiseen suureen juhlaan.",
        lang: "fi",
        en:
          "You made the flowers for our wedding a couple of years ago, so it was lovely to have flowers from you for our daughter's first big celebration too.",
        name: "Aino",
        occasion: ~t"Christening"
      }
    ]
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
      <section class="not-last:border-b">
        <div class="container grid items-center gap-10 pt-28 pb-16 sm:pt-(--header-clearance) md:grid-cols-2 md:gap-16 md:pb-24 lg:gap-24">
          <.image
            src="local:///jennie_1.jpg"
            alt={~t"Jennie holding a bouquet in front of an old blue door"}
            width={800}
            height={1000}
            crop="3200:4000:fp:0.4:0.5"
            sizes="(min-width: 768px) 50vw, 100vw"
            sources={[%{media: "(max-width: 767px)", width: 800, height: 800, crop: "3200:3200:fp:0.4:0.4"}]}
            priority
            class="aspect-square w-full object-cover md:aspect-[4/5]"
          />

          <div class="flex flex-col gap-4">
            <.flower name="flower-41" class="text-base-content/40 mb-4 h-12 w-12" />
            <p class="text-base-content/70 font-serif text-2xl italic">{~t"Hi, I'm Jennie"}</p>
            <h1 class="pull-quote max-w-xl">
              {~t"Here's a little about me, how it all started and how I work with flowers."}
            </h1>
          </div>
        </div>
      </section>

      <.story_section id="start" title={~t"How it started"}>
        <p>
          {~t"I was born and raised in Vaasa. I took a couple of florist courses while I was living in Stockholm, and I wanted to try something new. When my studies were finished, I felt something was missing in Vaasa when it came to flowers."}
        </p>
        <p>
          {~t"So in January 2019 I started Eden Flowers. Ordering should be easy. You don't need to choose between a million styles and flowers: just trust my taste, and I'll take care of the rest."}
        </p>
        <p>
          {~t"Today I live in Vaasa with my little family: my husband, our son and our dog."}
        </p>
      </.story_section>

      <section class="not-last:border-b" aria-labelledby="style-heading">
        <div class="grid md:grid-cols-2">
          <figure class="relative">
            <.image
              src="local:///image_4.jpg"
              alt={~t"A bouquet of white, peach and rust flowers held against dry autumn grass"}
              width={1000}
              height={1250}
              sizes="(min-width: 768px) 50vw, 100vw"
              class="aspect-[4/5] h-full w-full object-cover md:aspect-auto md:min-h-[640px]"
            />
            <figcaption class="text-white/80 absolute right-4 bottom-3 text-xs">
              {~t"Photo:"}
              <a
                href="https://www.danielastreng.com/"
                target="_blank"
                rel="noopener noreferrer"
                class="link-underline-hover hover:text-white"
              >
                Daniela Streng
              </a>
            </figcaption>
          </figure>

          <div class="flex flex-col justify-center gap-6 px-4 py-20 sm:px-8 md:px-12 lg:px-20">
            <h2 id="style-heading" class="section-title">{~t"My style"}</h2>
            <div class="text-base-content/80 flex max-w-prose flex-col gap-5 text-lg leading-relaxed">
              <p>
                {~t"My bouquets are mostly warm, neutral colours with some greenery. I choose flowers I know will last a long time, so you can enjoy them for longer."}
              </p>
              <p>
                {~t"I love using flowers that are in season, because in a little while they'll be gone again."}
              </p>
            </div>
          </div>
        </div>
      </section>

      <.story_section id="work" title={~t"How I work"}>
        <p>
          {~t"Usually it's just me, from your first message to the finished flowers. At busy times my family helps out with deliveries."}
        </p>
        <p>
          {~t"My shop is in Minimossen, the recycling mall at Myrvägen 1. Come by for a bouquet, a houseplant or a second-hand vase to put your flowers in."}
        </p>
      </.story_section>

      <section class="bg-cream not-last:border-b" aria-labelledby="quotes-heading">
        <div class="container py-20 md:py-28">
          <h2 id="quotes-heading" class="section-title mb-12">{~t"Kind words"}</h2>
          <ul class="grid gap-12 md:grid-cols-3 md:gap-8">
            <li :for={quote <- @quotes}>
              <.customer_quote
                quote={quote.text}
                lang={quote.lang}
                en={quote.en}
                name={quote.name}
                occasion={quote.occasion}
              />
            </li>
          </ul>
        </div>
      </section>

      <.trusted_by />

      <section class="bg-forest not-last:border-b" aria-labelledby="message-heading">
        <div class="grid md:grid-cols-2">
          <.image
            src="local:///jennie_5.JPG"
            alt={~t"Jennie smiling down at a bouquet of dahlias and eucalyptus"}
            width={1000}
            height={1250}
            crop="3200:4000:fp:0.45:0.5"
            sizes="(min-width: 768px) 50vw, 100vw"
            class="aspect-[4/5] max-h-[640px] h-full w-full object-cover md:aspect-auto md:h-[640px] md:order-last"
          />

          <div class="flex flex-col items-start gap-8 px-4 py-20 sm:px-8 md:justify-center md:px-12 lg:px-20">
            <.flower name="flower-30" class="text-forest-content/70 h-12 w-12" />
            <h2 id="message-heading" class="pull-quote text-forest-content max-w-xl">
              {~t"Whether it's a bouquet for the kitchen table or flowers for your wedding, I'd love to hear from you."}
            </h2>
            <.button phx-click={ContactDrawer.open()} variant="inverse">{~t"Send me a message"}</.button>
          </div>
        </div>
      </section>

      <.live_component module={ContactDrawer} id="contact-drawer" />
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp story_section(assigns) do
    ~H"""
    <section class="not-last:border-b" aria-labelledby={"#{@id}-heading"}>
      <div class="container grid gap-6 py-20 md:grid-cols-[1fr_2fr] md:gap-16 md:py-28 lg:gap-24">
        <h2 id={"#{@id}-heading"} class="section-title">{@title}</h2>
        <div class="text-base-content/80 flex max-w-prose flex-col gap-5 text-lg leading-relaxed">
          {render_slot(@inner_block)}
        </div>
      </div>
    </section>
    """
  end
end
