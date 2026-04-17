defmodule EdenflowersWeb.ClosedLive do
  use EdenflowersWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="relative min-h-screen">
      <img
        src={"local:///image_1.jpg" |> Imgproxy.new() |> Imgproxy.resize(1200, 1200, type: "fill") |> to_string()}
        class="absolute inset-0 h-full w-full object-cover"
        alt=""
      />
      <div class="bg-black/30 relative flex min-h-screen flex-col items-center justify-center gap-8 px-4 text-center text-white">
        <h1 class="font-serif text-4xl font-light tracking-wide sm:text-5xl">
          Eden Flowers
        </h1>
        <p class="max-w-[50ch] text-lg font-light leading-relaxed">
          Eden Flowers är för tillfället stängd pga mammaledighet. Har du förfrågning gällande bröllop, möhippa eller andra större event- ta kontakt via
          <a href="mailto:info@edenflowers.fi" class="underline underline-offset-4">info@edenflowers.fi</a>
        </p>
        <p class="max-w-[50ch] text-lg font-light leading-relaxed">
          Eden Flowers on tällä hetkellä suljettu äitiysloman vuoksi. Jos sinulla on tiedusteluja koskien häitä, polttareita tai muita suurempia tapahtumia, ota yhteyttä osoitteeseen
          <a href="mailto:info@edenflowers.fi" class="underline underline-offset-4">info@edenflowers.fi</a>
        </p>
      </div>
    </div>
    """
  end
end
