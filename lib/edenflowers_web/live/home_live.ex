defmodule EdenflowersWeb.HomeLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Store.Product

  def mount(_params, _session, socket) do
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
      <div class="space-y-6 py-16 sm:space-y-8 sm:py-24">
        <h2 class="font-serif px-2 text-3xl sm:text-4xl">{gettext("Shop Flowers")}</h2>
        
    <!-- Product slider container -->
        <div class="relative">
          <!-- Horizontal scrollable container -->
          <div class="scrollbar-thin scrollbar-thumb-gray-300 scrollbar-track-transparent flex snap-x snap-mandatory overflow-x-auto pb-6">
            <!-- Product cards -->
            <ul class="flex space-x-2 px-2 sm:space-x-4 md:px-4" role="list">
              <li :for={product <- @products} class="w-2/5 flex-none snap-center xs:w-1/2 sm:w-72 md:w-64">
                <a href="#" aria-labelledby={product.name} class="flex flex-col transition duration-300 hover:opacity-90">
                  <div class="mb-2 overflow-hidden rounded-lg">
                    <img
                      src={product.image}
                      alt={"#{product.name} image"}
                      class="aspect-square w-full object-cover transition duration-500 hover:scale-105"
                    />
                  </div>
                  <div class="text-base-content flex flex-col items-center">
                    <h3 id={product.name} class="font-serif text-lg sm:text-xl md:text-2xl">{product.name}</h3>
                    <p class="mt-1 text-sm sm:text-base">{Edenflowers.Utils.format_money(Decimal.new("70.00"))}</p>
                  </div>
                </a>
              </li>
            </ul>
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
