defmodule EdenflowersWeb.Marketing.CondolencesLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @thumb_width 480

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: ~t"Condolences",
       page_description:
         ~t"Funeral flowers in Vaasa and Korsholm: sprays, hearts, wreaths and casket sprays by Jennie at Eden Flowers, delivered to churches and chapels.",
       og_image: image_url("local:///condolence/condolence_5.jpg", 1200, 630)
     )
     |> assign(gallery: gallery(), thumb_width: @thumb_width)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <h1 class="page-title mb-6">{~t"Condolences"}</h1>
        <p class="text-base-content/80 max-w-prose text-lg leading-relaxed">
          {~t"At a final farewell, let the flowers be a place for your eyes to rest. I create both traditional and personal funeral arrangements, and deliver to churches and chapels in Vaasa and Korsholm for a small fee."}
        </p>
      </.container>

      <section class="bg-cream not-last:border-b" aria-labelledby="work-heading">
        <div class="container py-24">
          <h2 id="work-heading" class="section-title mb-10">{~t"My work"}</h2>
          <div
            id="condolence-gallery"
            phx-hook="PhotoGallery"
            class="columns-2 gap-3 md:columns-3 xl:columns-4"
          >
            <a
              :for={photo <- @gallery}
              href={image_url(photo.src, photo.width, photo.height)}
              data-pswp-width={photo.width}
              data-pswp-height={photo.height}
              target="_blank"
              rel="noreferrer"
              class="mb-3 block break-inside-avoid"
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
              <span class="sr-only">{~t"(opens a larger view)"}</span>
            </a>
          </div>
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
      %{
        src: "local:///condolence/condolence_2.jpg",
        width: 2000,
        height: 1500,
        alt: ~t"Spray of red roses and white lilies"
      },
      portrait(33, ~t"Spray of red roses and protea"),
      portrait(29, ~t"Open heart of pink and white carnations"),
      portrait(16, ~t"Spray of white lilies, pale pink roses and green carnations"),
      portrait(10, ~t"Spray of red roses, blue irises and white lisianthus"),
      portrait(18, ~t"Spray of orange roses and gypsophila"),
      portrait(27, ~t"All-white spray of lilies and lisianthus"),
      portrait(6, ~t"Spray of yellow roses and white carnations"),
      portrait(23, ~t"Spray of white roses and blue irises"),
      portrait(13, ~t"Spray of red carnations, purple lisianthus and gypsophila"),
      %{
        src: "local:///condolence/condolence_8.jpg",
        width: 1664,
        height: 1664,
        alt: ~t"Casket spray of meadow flowers and palm leaves on a white coffin"
      },
      portrait(11, ~t"Spray of coral roses and white lisianthus"),
      portrait(31, ~t"Spray of white roses and lilac lisianthus"),
      portrait(17, ~t"Spray of red and pink roses with white anemones"),
      portrait(21, ~t"Spray of white and lilac carnations with blue delphiniums"),
      portrait(19, ~t"Spray of pink roses, purple lisianthus and gypsophila"),
      portrait(22, ~t"Spray of peach roses and blue irises"),
      portrait(12, ~t"Spray of red roses and white spray roses"),
      portrait(25, ~t"Spray of red roses, blue gentians and gypsophila"),
      portrait(32, ~t"Spray of white carnations and blue delphiniums"),
      portrait(15, ~t"Spray of pale pink lisianthus and peach roses")
    ]
  end

  # Most photos are 3:4 phone shots.
  defp portrait(number, alt) do
    %{src: "local:///condolence/condolence_#{number}.jpg", width: 1500, height: 2000, alt: alt}
  end

  defp thumb_height(photo), do: round(@thumb_width * photo.height / photo.width)
end
