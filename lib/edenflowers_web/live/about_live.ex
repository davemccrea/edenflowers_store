defmodule EdenflowersWeb.AboutLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash}>
      <%!-- Hero --%>
      <section class="relative not-last:border-b">
        <img
          src={
            "local:///image_4.jpg"
            |> Imgproxy.new()
            |> Imgproxy.resize(1920, 600, type: "fill")
            |> to_string()
          }
          class="h-64 w-full object-cover sm:h-80 md:h-96"
          alt=""
        />
        <div class="bg-black/30 absolute inset-0 flex items-end">
          <div class="container pb-10">
            <h1 class="font-serif text-4xl tracking-wide text-white sm:text-5xl md:text-6xl">
              {~t"About"}
            </h1>
          </div>
        </div>
      </section>

      <%!-- Main content --%>
      <section class="not-last:border-b">
        <div class="container py-20 md:py-28">
          <div class="flex flex-col items-center gap-12 md:flex-row md:items-start md:gap-16 lg:gap-24">
            <%!-- Circular portrait --%>
            <div class="flex-shrink-0">
              <div class="h-56 w-56 overflow-hidden rounded-full sm:h-64 sm:w-64 md:h-72 md:w-72">
                <img
                  src={
                    "local:///jennie_pregnant.jpg"
                    |> Imgproxy.new()
                    |> Imgproxy.resize(400, 400, type: "fill")
                    |> Imgproxy.set_extension("webp")
                    |> to_string()
                  }
                  class="h-full w-full object-cover"
                  alt="Jennie"
                />
              </div>
            </div>

            <%!-- Text --%>
            <div class="text-base-content flex max-w-2xl flex-col gap-6">
              <h2 class="font-serif text-3xl sm:text-4xl">{~t"Hello, I'm Jennie"}</h2>
              <p class="text-base-content/80 text-lg leading-relaxed">
                Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
              </p>
              <p class="text-base-content/80 text-lg leading-relaxed">
                Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
              </p>
            </div>
          </div>
        </div>
      </section>

      <%!-- Full-bleed image --%>
      <section class="not-last:border-b">
        <img
          src={
            "local:///image_5.jpg"
            |> Imgproxy.new()
            |> Imgproxy.resize(1920, 800, type: "fill")
            |> Imgproxy.set_extension("webp")
            |> to_string()
          }
          class="h-72 w-full object-cover sm:h-96 md:h-[480px]"
          alt=""
        />
      </section>

      <%!-- Second text block --%>
      <section class="not-last:border-b">
        <div class="container py-20 md:py-28">
          <div class="text-base-content mx-auto flex max-w-2xl flex-col gap-6">
            <p class="text-base-content/80 text-lg leading-relaxed">
              Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis et quasi architecto beatae vitae dicta sunt explicabo.
            </p>
            <p class="text-base-content/80 text-lg leading-relaxed">
              Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit, sed quia consequuntur magni dolores eos qui ratione voluptatem sequi nesciunt.
            </p>
            <div class="pt-2">
              <.link navigate={~p"/contact"} class="btn btn-primary">
                {~t"Get in touch"}
              </.link>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
