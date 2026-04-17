defmodule EdenflowersWeb.ClosedLive do
  use EdenflowersWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="bg-base-200 flex min-h-screen flex-col">
      <header class="flex justify-center py-8">
        <img
          src={
            "local:///logo_header_250px.png"
            |> Imgproxy.new()
            |> Imgproxy.resize(250, 0, type: "fit")
            |> to_string()
          }
          class="h-28 w-auto"
          alt="Eden Flowers"
        />
      </header>

      <main class="flex flex-grow items-center justify-center px-6 py-8">
        <div class="flex w-full max-w-4xl flex-col items-center gap-8 md:flex-row md:items-center md:gap-12">
          <div class="order-2 w-full max-w-sm flex-shrink-0 md:order-1 md:w-96">
            <img
              src={
                "local:///jennie_pregnant.jpg"
                |> Imgproxy.new()
                |> Imgproxy.resize(800, 1000, type: "fill")
                |> to_string()
              }
              class="w-full rounded-lg object-cover shadow-sm"
              alt="Jennie"
            />
          </div>

          <div class="text-base-content order-1 flex flex-col gap-5 md:order-2 md:flex-1">
            <p class="text-lg font-light leading-relaxed">
              Eden Flowers är för tillfället stängd pga mammaledighet. Har du förfrågning gällande bröllop, möhippa eller andra större event- ta kontakt via
              <a href="mailto:info@edenflowers.fi" class="underline decoration-stone-400 underline-offset-4">
                info@edenflowers.fi
              </a>
            </p>
            <p class="text-lg font-light leading-relaxed">
              Eden Flowers on tällä hetkellä suljettu äitiysloman vuoksi. Jos sinulla on tiedusteluja koskien häitä, polttareita tai muita suurempia tapahtumia, ota yhteyttä osoitteeseen
              <a href="mailto:info@edenflowers.fi" class="underline decoration-stone-400 underline-offset-4">
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
