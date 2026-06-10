defmodule EdenflowersWeb.Marketing.MaternityLive do
  use EdenflowersWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="bg-base-200 flex min-h-screen flex-col">
      <header class="flex justify-center py-8">
        <.image
          src="local:///Eden_flowers-logo1_green_web.svg"
          alt="Eden Flowers"
          width={160}
          height={80}
          class="w-40 md:hidden"
        />
        <.image
          src="local:///Eden_flowers-logo2_green_web.svg"
          alt="Eden Flowers"
          width={256}
          height={80}
          class="hidden w-64 md:block"
        />
      </header>

      <main
        id="main-content"
        tabindex="-1"
        class="flex flex-grow items-center justify-center px-6 py-8 outline-hidden md:-mt-24"
      >
        <div class="flex w-full max-w-4xl flex-col items-center gap-8 md:flex-row md:items-center md:gap-12">
          <div class="order-2 w-full max-w-sm flex-shrink-0 md:order-1 md:w-96">
            <.image
              src="local:///jennie_pregnant.jpg"
              alt="Jennie"
              width={400}
              height={500}
              sizes="(min-width: 768px) 384px, 100vw"
              class="w-full rounded-md object-cover shadow-md"
            />
          </div>

          <div class="text-base-content order-1 flex flex-col gap-5 text-lg md:order-2 md:flex-1">
            <p>
              Eden Flowers är för tillfället stängd pga mammaledighet. Har du förfrågning gällande bröllop, möhippa eller andra större event- ta kontakt via
              <a
                href="mailto:info@edenflowers.fi"
                class="link-underline-static-body"
              >
                info@edenflowers.fi
              </a>
            </p>
            <p>
              Eden Flowers on tällä hetkellä suljettu äitiysloman vuoksi. Jos sinulla on tiedusteluja koskien häitä, polttareita tai muita suurempia tapahtumia, ota yhteyttä osoitteeseen
              <a
                href="mailto:info@edenflowers.fi"
                class="link-underline-static-body"
              >
                info@edenflowers.fi
              </a>
            </p>
          </div>
        </div>
      </main>
    </div>
    """
  end
end
