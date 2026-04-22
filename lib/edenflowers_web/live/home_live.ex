defmodule EdenflowersWeb.HomeLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Store.Product

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    products = Product.get_featured!()

    {:ok, socket |> assign(products: products)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash}>
      <section class="relative not-last:border-b">
        <img
          src={"local:///image_1.jpg" |> Imgproxy.new() |> Imgproxy.resize(1920, 1080, type: "fill") |> to_string()}
          class="h-[100vh] w-full object-cover"
          alt=""
        />

        <div class="from-black/50 absolute inset-0 bg-gradient-to-t via-transparent to-transparent" />

        <div class="container absolute inset-0 flex flex-col justify-center gap-5">
          <img
            src={"local:///Eden_flowers-logo1_white_web.svg" |> Imgproxy.new() |> to_string()}
            class="w-24 sm:w-36"
            alt="Eden Flowers"
          />
          <h1 class="font-serif max-w-[16ch] text-5xl font-light leading-tight text-white sm:text-6xl">
            {~t"Fresh flowers for everyday moments"}
          </h1>
          <div class="flex flex-wrap items-center gap-4">
            <a href="#store" class="btn-primary btn btn-lg gap-2">
              {~t"Shop Now"} <span aria-hidden="true">→</span>
            </a>
          </div>
        </div>
      </section>

      <section id="store" class="not-last:border-b">
        <div class="m-auto py-24 xl:max-w-[70vw]">
          <h2 class="section-title mb-4 px-2">{~t"Featured Blooms"}</h2>

          <div
            id="product-slider"
            style="scrollbar-width: thin;"
            class="flex snap-x snap-mandatory overflow-x-auto px-2 pb-6"
          >
            <ul class="flex space-x-2 py-2">
              <li :for={product <- @products} class="w-3/8 flex-none snap-center xs:w-1/2 sm:w-72">
                <.link
                  navigate={~p"/product/#{product}"}
                  aria-labelledby={product.name}
                  class="flex flex-col transition duration-100 hover:opacity-90"
                >
                  <div class="mb-2 overflow-hidden rounded-lg">
                    <img
                      src={product.image_slug |> Imgproxy.new() |> Imgproxy.resize(600, 600, type: "fill") |> to_string()}
                      alt={product.name}
                      class="aspect-square w-full object-cover"
                    />
                  </div>
                  <div class="text-base-content flex flex-col items-center">
                    <h3 id={product.name} class="card-title">{product.name}</h3>
                    <p class="text-sm">{Edenflowers.Utils.format_money(product.cheapest_price)}</p>
                  </div>
                </.link>
              </li>
            </ul>
          </div>
        </div>
      </section>

      <%!-- Pull quote --%>
      <section class="bg-amber-50 not-last:border-b">
        <div class="container flex flex-col items-center gap-12 py-24">
          <h1 class="font-serif max-w-4xl text-center text-3xl font-light leading-10 sm:leading-14 md:text-4xl">
            {~t"Crafted for those with discerning taste, our flowers blend quality and style and arrive perfectly arranged at your door."}
          </h1>
          <a class="font-bold uppercase tracking-wider underline underline-offset-4" href={~p"/about"}>
            {~t"Learn more"}
          </a>
        </div>
      </section>

      <%!-- Category tiles --%>
      <section class="bg-base-200 not-last:border-b">
        <div class="container py-20 md:py-28">
          <h2 class="font-serif mb-10 text-3xl">{~t"Start Here"}</h2>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <.link navigate={~p"/store"} class="group relative overflow-hidden">
              <img
                src="https://placehold.co/800x600/e8e0d8/888?text=Store"
                class="h-72 w-full object-cover transition duration-500 group-hover:scale-102 sm:h-80 md:h-96"
                alt={~t"Store"}
              />
              <div class="absolute inset-0 transition duration-500 group-hover:bg-black/10" />
              <div class="absolute inset-0 flex items-end p-6">
                <h3 class="font-serif text-2xl tracking-wide text-white">{~t"Store"}</h3>
              </div>
            </.link>

            <.link navigate={~p"/weddings"} class="group relative overflow-hidden">
              <img
                src="https://placehold.co/800x600/e8e0d8/888?text=Weddings"
                class="h-72 w-full object-cover transition duration-500 group-hover:scale-102 sm:h-80 md:h-96"
                alt={~t"Weddings"}
              />
              <div class="absolute inset-0 transition duration-500 group-hover:bg-black/10" />
              <div class="absolute inset-0 flex items-end p-6">
                <h3 class="font-serif text-2xl tracking-wide text-white">{~t"Weddings"}</h3>
              </div>
            </.link>

            <.link navigate={~p"/courses"} class="group relative overflow-hidden">
              <img
                src="https://placehold.co/800x600/e8e0d8/888?text=Courses"
                class="h-72 w-full object-cover transition duration-500 group-hover:scale-102 sm:h-80 md:h-96"
                alt={~t"Courses"}
              />
              <div class="absolute inset-0 transition duration-500 group-hover:bg-black/10" />
              <div class="absolute inset-0 flex items-end p-6">
                <h3 class="font-serif text-2xl tracking-wide text-white">{~t"Courses"}</h3>
              </div>
            </.link>

            <.link navigate={~p"/condolences"} class="group relative overflow-hidden">
              <img
                src="https://placehold.co/800x600/e8e0d8/888?text=Condolences"
                class="h-72 w-full object-cover transition duration-500 group-hover:scale-102 sm:h-80 md:h-96"
                alt={~t"Condolences"}
              />
              <div class="absolute inset-0 transition duration-500 group-hover:bg-black/10" />
              <div class="absolute inset-0 flex items-end p-6">
                <h3 class="font-serif text-2xl tracking-wide text-white">{~t"Condolences"}</h3>
              </div>
            </.link>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
