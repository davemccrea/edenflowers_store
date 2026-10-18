defmodule EdenflowersWeb.Marketing.WeddingsLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.WeddingEnquiry

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

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: ~t"Weddings",
       page_description:
         ~t"Wedding flowers in Vaasa and Korsholm: bridal bouquets, decoration and flower arches designed by Jennie at Eden Flowers. Prices and past weddings.",
       og_image: image_url("local:///wedding/daniela_streng_3.jpg", 1200, 630)
     )
     |> assign(gallery: gallery())
     |> assign(
       personal_flowers: personal_flowers(),
       decorations: decorations(),
       decoration_photos: decoration_photos(),
       quantities: %{"bridal_bouquet" => 1}
     )
     |> assign(enquiry_form: build_enquiry_form(%{}), enquiry_sent?: false)
     |> assign(steps: steps(), testimonial: testimonial())}
  end

  @impl true
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
                <.button href="#my-work" variant="primary">{~t"See my work"}</.button>
                <.button href="#prices" variant="secondary">{~t"Estimate your price"}</.button>
              </div>
            </div>

            <%!-- On desktop the width comes from the screen height, so the whole section fits one screen and no browser sizes the photo from its natural size. --%>
            <figure class="md:justify-self-end">
              <.image
                src="local:///wedding/anna_riska_2.jpg"
                alt={~t"Bride smiling with a colourful bridal bouquet"}
                width={800}
                height={1000}
                sizes="(min-width: 768px) 50vw, 100vw"
                priority
                class="aspect-[4/5] w-full object-cover object-top md:w-[calc((100dvh-var(--header-clearance)-6rem)*4/5)] md:max-w-full"
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
              <.gallery_photo photo={photo} />
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

      <section id="prices" class="scroll-anchor-below-header not-last:border-b" aria-labelledby="prices-heading">
        <div class="container py-24">
          <div class="grid items-start gap-10 md:grid-cols-[minmax(0,1fr)_18rem] md:gap-16 lg:grid-cols-[minmax(0,1fr)_22rem]">
            <div>
              <h2 id="prices-heading" class="section-title mb-4">{~t"Prices"}</h2>
              <p class="text-base-content/80 mb-10 max-w-prose text-lg leading-relaxed">
                {~t"Every wedding is different, so you'll get an exact quote once we've talked through your plans."}
              </p>
              <h3 class="tile-title mb-3">{~t"Bouquets and accessories"}</h3>
              <.price_list items={@personal_flowers} quantities={@quantities} />
              <h3 class="tile-title mt-12 mb-3">{~t"Decoration"}</h3>
              <.price_list items={@decorations} quantities={@quantities} />
            </div>

            <%!-- The header is fixed, so the sticky card has to clear it. --%>
            <div
              class="bg-cream text-cream-content p-8 md:top-[calc(var(--header-height)+2rem)] md:sticky"
              aria-labelledby="estimate-heading"
            >
              <h3 id="estimate-heading" class="eyebrow mb-4">{~t"Estimate"}</h3>
              <p id="wedding-estimate" class="font-serif text-5xl tabular-nums" aria-live="polite">
                {estimate_label(estimate(@personal_flowers ++ @decorations, @quantities))}
              </p>
              <p :if={selected?(@quantities, "cake_flowers")} id="estimate-cake-flowers" class="text-cream-content/80 mt-2">
                {~t"+ cake flowers on request"}
              </p>
              <p class="text-cream-content/70 mt-6 text-sm leading-relaxed">
                {~t"Final prices depend on the flowers and techniques you choose. Delivery outside Vaasa is quoted separately."}
              </p>
              <.button phx-click={open_enquiry()} variant="primary" class="mt-8 w-full">
                {~t"Request a quote"}
              </.button>
            </div>
          </div>

          <%!-- One 3:2 photo spanning two columns is as tall as the 3:4 photos beside it. --%>
          <div class="mt-20 grid grid-cols-2 gap-3 md:grid-cols-6 md:gap-6">
            <figure class="col-span-2">
              <.image
                src="local:///wedding/eden_flowers_2.jpg"
                alt={~t"Wrist corsages of peach roses"}
                width={800}
                height={533}
                sizes="(min-width: 48rem) 33vw, 100vw"
                class="aspect-[3/2] w-full object-cover"
              />
              <figcaption class="text-base-content/70 mt-2 text-sm"><.credit_line name="Eden Flowers" /></figcaption>
            </figure>
            <figure :for={photo <- @decoration_photos}>
              <.image
                src={photo.src}
                alt={photo.alt}
                width={600}
                height={800}
                sizes="(min-width: 48rem) 17vw, 50vw"
                class="aspect-[3/4] w-full object-cover"
              />
              <figcaption class="mt-2">{photo.caption}</figcaption>
            </figure>
          </div>
        </div>
      </section>

      <section class="not-last:border-b" aria-labelledby="process-heading">
        <div class="container py-24">
          <h2 id="process-heading" class="section-title mb-12">{~t"How it works"}</h2>
          <ol class="border-base-content/12 border-t">
            <li
              :for={{{title, body}, index} <- Enum.with_index(@steps, 1)}
              class="border-base-content/12 grid-cols-[3rem_1fr] grid gap-x-4 border-b py-8 md:grid-cols-[4rem_16rem_1fr] md:gap-x-8"
            >
              <p class="text-primary font-serif text-4xl font-light leading-none">{index}</p>
              <h3 class="card-heading">{title}</h3>
              <p class="text-base-content/80 col-start-2 mt-2 max-w-prose leading-relaxed md:col-start-3 md:mt-0">{body}</p>
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
            class="aspect-[4/5] max-h-[640px] h-full w-full object-cover object-top md:aspect-auto"
          />

          <div class="flex flex-col items-start gap-8 px-4 py-20 sm:px-8 md:justify-center md:px-12 lg:px-20">
            <.flower name="flower-30" class="text-forest-content/70 h-12 w-12" />
            <h2 id="enquire-heading" class="section-title text-forest-content">{~t"Planning a wedding?"}</h2>
            <p class="text-forest-content/85 max-w-prose text-lg leading-relaxed">
              {~t"I'm Jennie, and I design every wedding myself, from our first conversation to the flowers on the day. Tell me your date, your venue and roughly how many guests you're expecting. If there are photos here you love, mention those too."}
            </p>
            <.button phx-click={open_enquiry()} variant="inverse">{~t"Request a quote"}</.button>
            <p class="text-forest-content/85">
              {~t"Or call me on"}
              <a href="tel:+358402209494" class="link-underline-static-body whitespace-nowrap">040 220 9494</a>
            </p>
          </div>
        </div>
      </section>

      <.drawer
        id="enquiry-drawer"
        placement="right"
        label={~t"Request a quote"}
        class="bg-base-100 w-[92vw] h-full overflow-y-auto sm:w-[34rem]"
      >
        <div class="flex flex-col gap-6 p-6 sm:p-10">
          <header class="flex items-center justify-between">
            <h2 class="section-title">{~t"Request a quote"}</h2>
            <.icon_button aria_label={~t"Close"} phx-click={JS.exec("phx-hide", to: "#enquiry-drawer")}>
              <.icon name="hero-x-mark" class="h-6 w-6" />
            </.icon_button>
          </header>
          <p :if={!@enquiry_sent?} class="text-base-content/80 leading-relaxed">
            {~t"Tell me about your wedding and I'll send you a quote."}
          </p>
          <.enquiry_form
            :if={!@enquiry_sent?}
            form={@enquiry_form}
            selection={selection_lines(@personal_flowers ++ @decorations, @quantities)}
            estimate={estimate_label(estimate(@personal_flowers ++ @decorations, @quantities))}
          />
          <div :if={@enquiry_sent?} id="enquiry-sent" class="flex flex-col gap-3">
            <p class="font-serif text-3xl">{~t"Thank you!"}</p>
            <p class="text-base-content/80">
              {~t"Your enquiry is on its way, and a copy is in your inbox. I'll get back to you with a quote as soon as I can. Nothing is booked until you confirm it."}
            </p>
          </div>
        </div>
      </.drawer>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate_enquiry", %{"enquiry" => params}, socket) do
    {:noreply, assign(socket, enquiry_form: build_enquiry_form(params, :validate))}
  end

  def handle_event("send_enquiry", %{"enquiry" => params}, socket) do
    items = socket.assigns.personal_flowers ++ socket.assigns.decorations
    quantities = socket.assigns.quantities
    estimate = estimate_label(estimate(items, quantities))
    locale = to_string(Edenflowers.Format.locale())

    case WeddingEnquiry.submit(params, selection_lines(items, quantities), estimate, locale) do
      :ok ->
        {:noreply, assign(socket, enquiry_sent?: true)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, enquiry_form: to_form(changeset, as: :enquiry))}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, ~t"Your enquiry couldn't be sent. Please try again, or email me directly.")}
    end
  end

  def handle_event("change_quantity", %{"item" => id, "by" => by}, socket) when by in ["1", "-1"] do
    {:noreply, update_quantity(socket, id, &max(&1 + String.to_integer(by), 0))}
  end

  defp update_quantity(socket, id, fun) do
    if Enum.any?(socket.assigns.personal_flowers ++ socket.assigns.decorations, &(&1.id == id)) do
      update(socket, :quantities, fn quantities -> Map.update(quantities, id, fun.(0), fun) end)
    else
      socket
    end
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
        src: "local:///wedding/bjorn_yrjans_2.jpg",
        width: 1335,
        height: 2000,
        credit: "Björn Yrjans",
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
      %{id: "bridal_bouquet", label: ~t"Bridal bouquet", price: {:range, 110, 190}},
      %{id: "bridesmaid_bouquet", label: ~t"Bridesmaid's bouquet", price: {:from, 45}},
      %{id: "flower_girl_bouquet", label: ~t"Flower girl or toss bouquet", price: {:from, 35}},
      %{id: "corsage", label: ~t"Corsage or pocket square", price: {:from, 19}},
      %{id: "hair_flowers", label: ~t"Hair and wrist flowers (crown, clip, tiara, bracelet)", price: {:from, 32}},
      %{id: "cake_flowers", label: ~t"Cake flowers", price: :on_request}
    ]
  end

  defp decorations do
    [
      %{id: "silk_garland", label: ~t"Silk flower garland, to rent", price: {:fixed, 95}},
      %{id: "flower_arch", label: ~t"Flower arch or flower gate", price: {:from, 320}},
      %{id: "urn_arrangement", label: ~t"Arrangement in an urn or on a pedestal", price: {:from, 95}},
      %{id: "welcome_sign", label: ~t"Welcome sign arrangement", price: {:from, 70}}
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

  defp selection_lines(items, quantities) do
    for item <- items, selected?(quantities, item.id) do
      if item.price == :on_request, do: item.label, else: "#{quantities[item.id]} × #{item.label}"
    end
  end

  # ponytail: "from" prices have no ceiling, so they count at their lowest at
  # both ends and the range is too narrow. Give each item a range to fix it.
  defp estimate(items, quantities) do
    {Enum.sum_by(items, &(low_price(&1.price) * Map.get(quantities, &1.id, 0))),
     Enum.sum_by(items, &(high_price(&1.price) * Map.get(quantities, &1.id, 0)))}
  end

  defp low_price(:on_request), do: 0
  defp low_price({:fixed, euros}), do: euros
  defp low_price({:range, low, _high}), do: low
  defp low_price({:from, low}), do: low

  defp high_price({:range, _low, high}), do: high
  defp high_price(price), do: low_price(price)

  defp selected?(quantities, id), do: Map.get(quantities, id, 0) > 0

  defp estimate_label({same, same}), do: euros(same)
  defp estimate_label({low, high}), do: price_label({:range, low, high})

  defp open_enquiry, do: JS.exec("phx-show", to: "#enquiry-drawer")

  # Errors only show once the couple has touched a field or tried to send.
  defp build_enquiry_form(params, action \\ nil) do
    params
    |> WeddingEnquiry.changeset()
    |> Map.put(:action, action)
    |> to_form(as: :enquiry)
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :selection, :list, required: true
  attr :estimate, :string, required: true

  defp enquiry_form(assigns) do
    ~H"""
    <.form for={@form} id="enquiry-form" phx-change="validate_enquiry" phx-submit="send_enquiry" class="flex flex-col gap-4">
      <div :if={@selection != []} class="bg-cream text-cream-content p-4 text-sm">
        <p class="eyebrow mb-2">{~t"Flowers you're interested in"}</p>
        <ul class="space-y-0.5">
          <li :for={line <- @selection}>{line}</li>
        </ul>
        <p class="font-serif mt-2 text-lg">{@estimate}</p>
      </div>

      <div class="grid gap-4 sm:grid-cols-2">
        <.input field={@form[:name]} label={~t"Your name *"} autocomplete="name" aria-required="true" />
        <.input field={@form[:email]} type="email" label={~t"Email *"} autocomplete="email" aria-required="true" />
        <.input field={@form[:wedding_date]} type="date" label={~t"Wedding date *"} aria-required="true" />
        <.input field={@form[:guests]} type="number" min="1" label={~t"Number of guests"} />
      </div>
      <.input field={@form[:venue]} label={~t"Venue"} />
      <.input field={@form[:message]} type="textarea" label={~t"Colours, flowers and anything else"} />
      <%!-- Honeypot: hidden from people, so only bots fill it in. --%>
      <.input field={@form[:website]} hidden tabindex="-1" autocomplete="off" aria-hidden="true" />

      <.button type="submit" variant="primary" phx-disable-with={~t"Sending…"}>{~t"Send enquiry"}</.button>
      <p class="text-base-content/70 text-sm">
        {~t"Or email me directly at"}
        <a href="mailto:info@edenflowers.fi" class="link-underline-static-body">info@edenflowers.fi</a>
      </p>
    </.form>
    """
  end

  attr :items, :list, required: true
  attr :quantities, :map, required: true

  defp price_list(assigns) do
    ~H"""
    <dl class="border-t">
      <div :for={item <- @items} class="flex items-center justify-between gap-6 border-b py-3">
        <div>
          <dt class="text-lg">{item.label}</dt>
          <dd class="text-base-content font-serif text-lg tabular-nums">{price_label(item.price)}</dd>
        </div>
        <dd class="shrink-0">
          <.quantity_picker item={item} quantity={Map.get(@quantities, item.id, 0)} />
        </dd>
      </div>
    </dl>
    """
  end

  attr :item, :map, required: true
  attr :quantity, :integer, required: true

  defp quantity_picker(%{item: %{price: :on_request}} = assigns) do
    ~H"""
    <label class="touch-target inline-flex">
      <input
        type="checkbox"
        class="checkbox"
        checked={@quantity > 0}
        phx-click="change_quantity"
        phx-value-item={@item.id}
        phx-value-by={if @quantity > 0, do: "-1", else: "1"}
        aria-label={~t"Add to the estimate: #{@item.label}"}
      />
    </label>
    """
  end

  defp quantity_picker(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <.icon_button
        size="lg"
        disabled={@quantity == 0}
        phx-click="change_quantity"
        phx-value-item={@item.id}
        phx-value-by="-1"
        aria_label={~t"Remove one: #{@item.label}"}
      >
        <.icon class="h-4 w-4" name="hero-minus-mini" />
      </.icon_button>
      <span class="w-6 text-center tabular-nums" aria-label={~t"Quantity"}>{@quantity}</span>
      <.icon_button
        size="lg"
        phx-click="change_quantity"
        phx-value-item={@item.id}
        phx-value-by="1"
        aria_label={~t"Add one: #{@item.label}"}
      >
        <.icon class="h-4 w-4" name="hero-plus-mini" />
      </.icon_button>
    </div>
    """
  end

  defp price_label(:on_request), do: ~t"On request"
  defp price_label({:fixed, euros}), do: euros(euros)
  defp price_label({:range, low, high}), do: "#{euros(low)}–#{euros(high)}"

  defp price_label({:from, low}) do
    amount = euros(low)
    ~t"from #{amount}"
  end

  defp euros(amount), do: Edenflowers.Format.storefront_price(amount, Edenflowers.Format.locale())

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
end
