defmodule EdenflowersWeb.Marketing.CondolencesLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: ~t"Condolences",
       page_description:
         ~t"Funeral flowers in Vaasa and Korsholm: sprays, hearts, wreaths and casket sprays by Jennie at Eden Flowers, delivered to churches and chapels.",
       og_image: image_url("local:///condolence/condolence_5.jpg", 1200, 630)
     )
     |> assign(gallery: gallery(), order_mailto: order_mailto())}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <section class="flex items-center not-last:border-b md:min-h-dvh">
        <div class="container pt-28 pb-20 sm:pt-(--header-clearance) md:pb-16">
          <div class="grid items-center gap-10 md:grid-cols-2 md:gap-16">
            <div>
              <h1 class="page-title mb-6">{~t"Condolences"}</h1>
              <p class="text-base-content/80 max-w-prose text-lg leading-relaxed">
                {~t"At a final farewell, let the flowers be a place for your eyes to rest. I create both traditional and personal funeral arrangements, and deliver to churches and chapels in Vaasa and Korsholm for a small fee."}
              </p>
              <div class="mt-8 flex flex-wrap items-center gap-6">
                <.button href="#order" variant="primary">{~t"Order funeral flowers"}</.button>
                <.button href="#my-work" variant="text">{~t"See my work"}</.button>
              </div>
            </div>

            <%!-- On desktop the photo's height is capped so the whole section fits one screen. --%>
            <figure class="md:justify-self-end">
              <.image
                src="local:///condolence/condolence_5.jpg"
                alt={~t"Solid heart of red roses and white carnations"}
                width={750}
                height={1000}
                sizes="(min-width: 768px) 50vw, 100vw"
                priority
                class="aspect-[3/4] w-full object-cover md:max-h-[calc(100dvh-var(--header-clearance)-6rem)] md:w-auto"
              />
            </figure>
          </div>
        </div>
      </section>

      <section id="my-work" class="bg-cream scroll-anchor-below-header not-last:border-b" aria-labelledby="work-heading">
        <div class="container py-24">
          <h2 id="work-heading" class="section-title mb-10">{~t"My work"}</h2>
          <div
            id="condolence-gallery"
            phx-hook="PhotoGallery"
            class="columns-2 gap-3 md:columns-3 xl:columns-4"
          >
            <.gallery_photo :for={photo <- @gallery} photo={photo} class="mb-3 break-inside-avoid" />
          </div>
        </div>
      </section>

      <section id="order" class="bg-forest scroll-anchor-below-header not-last:border-b" aria-labelledby="order-heading">
        <div class="container flex flex-col items-center gap-8 py-24 text-center md:py-32">
          <.flower name="flower-30" class="text-forest-content/70 h-12 w-12" />
          <h2 id="order-heading" class="section-title text-forest-content">{~t"Ordering for a funeral"}</h2>
          <p class="text-forest-content/85 max-w-prose text-lg leading-relaxed">
            {~t"Call me and we'll choose the flowers together. Tell me the date and time of the funeral, the church or chapel, and what you'd like written on the card. If there's an arrangement here you like, mention that too."}
          </p>
          <.button href="tel:+358402209494" variant="inverse">{~t"Call me on 040 220 9494"}</.button>
          <p class="text-forest-content/85">
            {~t"Or"}
            <a href={@order_mailto} class="link-underline-static-body">{~t"email me"}</a>
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end

  # width/height are the dimensions PhotoSwipe opens the photo at, and the
  # exact size Imgproxy is asked for — the two must agree. Keep each entry's
  # ratio equal to the source photo's so the fill crop is a no-op.
  # Ordered by strength and to spread out similar arrangements.
  defp gallery do
    [
      portrait(5, ~t"Solid heart of red roses and white carnations"),
      portrait(7, ~t"Wreath of yellow roses, anemones and peach carnations"),
      portrait(34, ~t"Spray of white lilies and chrysanthemums"),
      %{
        src: "local:///condolence/condolence_1.jpg",
        width: 2000,
        height: 1333,
        alt: ~t"Casket spray of pink carnations and roses on a wooden coffin"
      },
      portrait(14, ~t"Open heart of red roses"),
      portrait(3, ~t"Hand-tied bouquet of red roses tied with a hessian bow"),
      portrait(28, ~t"Spray of white roses and blue delphiniums"),
      portrait(4, ~t"Open heart of white roses and lilac carnations"),
      portrait(35, ~t"Spray of yellow roses and chrysanthemums"),
      portrait(33, ~t"Spray of red roses and protea"),
      portrait(6, ~t"Spray of yellow roses and white carnations"),
      portrait(23, ~t"Spray of white roses and blue irises"),
      portrait(13, ~t"Spray of red carnations, purple lisianthus and gypsophila"),
      %{
        src: "local:///condolence/condolence_8.jpg",
        width: 1664,
        height: 1664,
        alt: ~t"Casket spray of meadow flowers and palm leaves on a white coffin"
      },
      portrait(22, ~t"Spray of peach roses and blue irises")
    ]
  end

  # Most photos are 3:4 phone shots.
  defp portrait(number, alt) do
    %{src: "local:///condolence/condolence_#{number}.jpg", width: 1500, height: 2000, alt: alt}
  end

  defp order_mailto do
    subject = URI.encode(~t"Funeral flowers", &URI.char_unreserved?/1)

    body =
      [~t"Date and time of the funeral:", ~t"Church or chapel:", ~t"Arrangement:", ~t"Card message:"]
      |> Enum.map_join("\n", &(&1 <> " "))
      |> URI.encode(&URI.char_unreserved?/1)

    "mailto:info@edenflowers.fi?subject=#{subject}&body=#{body}"
  end
end
