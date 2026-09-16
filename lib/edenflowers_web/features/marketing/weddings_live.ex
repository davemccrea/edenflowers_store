defmodule EdenflowersWeb.Marketing.WeddingsLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @thumb_width 400

  # width/height are the dimensions PhotoSwipe opens the photo at, and the
  # exact size Imgproxy is asked for — the two must agree. Keep each entry's
  # ratio equal to the source photo's so the fill crop is a no-op.
  # Slugs resolve against the Imgproxy local source.
  @gallery [
    %{
      src: "local:///image_1.jpg",
      alt: "Bridal bouquet",
      width: 1600,
      height: 2000,
      credit: "Photo: Anna Virtanen"
    },
    %{src: "local:///image_4.jpg", alt: "Ceremony arch", width: 2000, height: 1333, credit: nil},
    %{
      src: "local:///image_5.jpg",
      alt: "Table centrepiece",
      width: 1600,
      height: 2000,
      credit: "Photo: Anna Virtanen"
    }
  ]

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(gallery: @gallery, thumb_width: @thumb_width)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <h1 class="page-title">{~t"Weddings"}</h1>

        <h2 class="section-title mt-16">{~t"Gallery"}</h2>

        <div id="wedding-gallery" phx-hook="PhotoGallery" class="mt-4 columns-2 gap-4 md:columns-3">
          <figure :for={photo <- @gallery} class="mb-4 break-inside-avoid">
            <a
              href={image_url(photo.src, photo.width, photo.height)}
              data-pswp-width={photo.width}
              data-pswp-height={photo.height}
              data-pswp-credit={photo.credit}
              target="_blank"
              rel="noreferrer"
              class="block"
            >
              <.image
                src={photo.src}
                alt={photo.alt}
                width={@thumb_width}
                height={thumb_height(photo)}
                sizes="(min-width: 768px) 33vw, 50vw"
                class="w-full rounded-md"
              />
            </a>

            <figcaption :if={photo.credit} class="text-base-content/60 mt-1 text-xs">
              {photo.credit}
            </figcaption>
          </figure>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  defp thumb_height(photo), do: round(@thumb_width * photo.height / photo.width)
end
