defmodule EdenflowersWeb.Marketing.WeddingsLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  # Largest column: (1536px container - 64px padding - 32px gaps) / 3.
  @thumb_width 480

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
      src: "local:///wedding/anna_riska_2.jpg",
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
      src: "local:///wedding/björn_yrjans.jpg",
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
    %{
      src: "local:///wedding/eden_flowers_2.jpg",
      width: 2000,
      height: 1333,
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
      src: "local:///wedding/sara_björkskog.jpg",
      width: 1334,
      height: 2000,
      credit: "Sara Björkskog"
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

        <div id="wedding-gallery" phx-hook="PhotoGallery" class="mt-2 columns-2 gap-2 md:columns-3">
          <figure :for={{photo, index} <- Enum.with_index(@gallery)} class="mb-2 break-inside-avoid">
            <a
              href={image_url(photo.src, photo.width, photo.height)}
              data-pswp-width={photo.width}
              data-pswp-height={photo.height}
              data-pswp-credit={photo.credit && ~t"Photo: #{photo.credit}"}
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
                sizes="(min-width: 96rem) 30rem, (min-width: 80rem) calc(74rem / 3), (min-width: 64rem) calc(58rem / 3), (min-width: 48rem) 14rem, (min-width: 40rem) 17.5rem, calc((100vw - 3rem) / 2)"
                class="w-full rounded-md"
              />
            </a>
          </figure>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  defp thumb_height(photo), do: round(@thumb_width * photo.height / photo.width)
end
