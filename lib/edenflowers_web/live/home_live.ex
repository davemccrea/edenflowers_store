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
      <div class="container py-24">
        <h2 class="font-serif text-3xl">{gettext("Shop Flowers")}</h2>

        <div class="scrollbar-hide flex snap-x snap-mandatory gap-6 overflow-x-auto py-8">
          <div class="-translate-y-[calc(var(--spacing)*0.25)] touch-manipulation select-none shadow-md transition-all duration-75 ease-in active:translate-0 active:shadow-none">
            <div :for={product <- @products} class="bg-base-300 snap-center border">
              <div class="relative">
                <img src="/images/ai_placeholder_1.png" alt="Product 1" class="aspect-square w-64 border-b object-cover" />
              </div>
              <div class="text-base-content flex flex-col items-center p-3">
                <h3 class="font-serif text-xl">{product.name}</h3>
                <span class="text-sm">{Edenflowers.Utils.format_money(Decimal.new("70.00"))}</span>
              </div>
            </div>
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
