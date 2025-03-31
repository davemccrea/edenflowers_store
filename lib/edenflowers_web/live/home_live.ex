defmodule EdenflowersWeb.HomeLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Store.Product

  def mount(_params, session, socket) do
    # TODO: get only main products
    products = Ash.read!(Product)

    {:ok, socket |> assign(products: products)}
  end

  def render(assigns) do
    ~H"""
    <section class="relative not-last:border-b">
      <img src="/images/image_1.jpg" class="h-[100vh] w-full object-cover" alt="" />

      <div class="container absolute inset-0 flex flex-col items-center justify-center gap-8 text-center">
        <h1 class="hero-heading text-image font-serif max-w-[20ch] tracking-wide">
          {gettext("Fresh flowers for everyday moments.")}
        </h1>
        <button class="btn btn-primary mx-auto lg:btn-lg">{gettext("Shop Now")}</button>
      </div>
    </section>

    <section class="not-last:border-b">
      <div class="space-y-8 py-24">
        <h2 class="font-serif px-2 text-4xl">{gettext("Shop Flowers")}</h2>

        <div id="product-swiper" phx-hook="ProductSwiper" class="swiper">
          <ul class="swiper-wrapper" role="list">
            <li :for={product <- @products} class="swiper-slide select-none py-2">
              <a href="#" aria-labelledby={product.name} class="mb-4 flex flex-col">
                <img src={product.image} alt={"#{product.name} image"} class="mb-2 object-cover" />
                <div class="text-base-content flex flex-col items-center">
                  <h3 class="font-serif text-2xl">{product.name}</h3>
                  <p>{Edenflowers.Utils.format_money(Decimal.new("70.00"))}</p>
                </div>
              </a>
            </li>
          </ul>

          <div class="scrollbar-container">
            <div class="swiper-scrollbar"></div>
          </div>
        </div>
      </div>
    </section>

    <section class="not-last:border-b">
      <div class="container flex flex-col items-center gap-12 py-24">
        <h1 class="font-serif max-w-4xl text-center text-3xl font-light leading-10 sm:leading-14 md:text-4xl">
          {gettext(
            "Crafted for those with discerning taste, our flowers blend quality and style and arrive perfectly arranged at your door."
          )}
        </h1>
        <a class="font-bold uppercase tracking-wider underline underline-offset-4" href={~p"/#about"}>
          Learn more
        </a>
      </div>
    </section>
    """
  end
end
