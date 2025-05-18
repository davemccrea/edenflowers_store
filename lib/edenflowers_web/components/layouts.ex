defmodule EdenflowersWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use EdenflowersWeb, :controller` and
  `use EdenflowersWeb, :live_view`.
  """
  use EdenflowersWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :order, :map, required: true
  slot :inner_block, required: true

  def app(assigns) do
    {:ok, current_locale} = Edenflowers.Cldr.Language.to_string(Cldr.get_locale())

    assigns =
      assigns
      |> assign(
        nav: [
          {~p"/#store", gettext("Store")},
          {~p"/courses", gettext("Courses")},
          {~p"/weddings", gettext("Weddings")},
          {~p"/condolences", gettext("Condolences")},
          {~p"/about", gettext("About")},
          {~p"/contact", gettext("Contact")}
        ]
      )
      |> assign(current_locale: String.capitalize(current_locale))

    ~H"""
    <.drawer id="nav-drawer" placement="left" class="bg-base-200 border-r-1 w-[80vw] flex h-full flex-col sm:w-[25rem]">
      <header class="bg-accent-2 flex flex-row items-center justify-between pt-8 pr-4 pl-8">
        <.link
          navigate={~p"/"}
          class="text-primary font-sans whitespace-nowrap font-bold uppercase tracking-widest sm:text-2xl"
        >
          Eden Flowers
        </.link>

        <button type="button" phx-click={JS.exec("phx-hide", to: "#nav-drawer")} class="h-12 w-12 cursor-pointer">
          <.icon name="hero-x-mark" class="h-6 w-6 hover:text-base-content/60" />
        </button>
      </header>

      <div class="flex flex-1 flex-col justify-between p-8">
        <nav>
          <ul class="space-y-4">
            <li :for={{url, name} <- @nav}>
              <.link
                class="font-serif text-base-content text-2xl hover:decoration-(--color-accent-alt) hover:underline hover:underline-offset-4 sm:text-3xl"
                phx-click={JS.exec("phx-hide", to: "#nav-drawer")}
                navigate={url}
              >
                {name}
              </.link>
            </li>
          </ul>
        </nav>
      </div>

      <footer class="bg-base-300 flex flex-col px-8 py-8">
        <.social_media_links size={6} />
      </footer>
    </.drawer>

    <.drawer id="cart-drawer" placement="right" class="bg-base-200 border-l-1 w-[80vw] flex h-full flex-col sm:w-[25rem]">
      <header class="bg-accent-2 flex flex-row items-center justify-between pt-8 pr-4 pl-8">
        <h1 class="font-serif text-3xl">
          <%= if not is_nil(@order.total_items_in_cart) do %>
            {gettext("Cart")} ({@order.total_items_in_cart})
          <% else %>
            {gettext("Cart")}
          <% end %>
        </h1>

        <button phx-click={JS.exec("phx-hide", to: "#cart-drawer")} type="button" class="h-12 w-12 cursor-pointer">
          <.icon name="hero-x-mark" class="h-6 w-6 hover:text-base-content/60" />
        </button>
      </header>

      <div class="flex flex-1 flex-col justify-between overflow-y-auto p-8">
        <.live_component id="cart-line-items" module={EdenflowersWeb.LineItemsComponent} order={@order} />
      </div>

      <footer :if={Enum.any?(@order.line_items)} class="bg-base-300 flex flex-col px-8 py-8">
        <.link navigate={~p"/checkout"} phx-click={JS.exec("phx-hide", to: "#cart-drawer")} class="btn btn-primary">
          {gettext("Checkout")}
        </.link>
      </footer>
    </.drawer>

    <hotfx-shy-header>
      <header class="w-full">
        <%!-- Banner --%>
        <section class="border-b bg-sky-100 py-2 text-center">
          <span class="text-accent-content text-sm">{gettext("Let us know what you think of the new website! 🚀")}</span>
        </section>

        <%!-- Main header --%>
        <section class="bg-base-100 border-b px-3 py-2 sm:px-6 sm:py-4">
          <div class="flex items-center">
            <%!-- Left --%>
            <div class="flex flex-1 justify-start">
              <%!-- Mobile hamburger menu --%>
              <div class="block xl:hidden">
                <button
                  phx-click={JS.exec("phx-show", to: "#nav-drawer")}
                  type="button"
                  class="h-12 w-12 cursor-pointer"
                  aria-label={gettext("Open navigation menu")}
                >
                  <.icon name="hero-bars-3-bottom-left" class="text-base-content h-6 w-6 hover:text-base-content/60" />
                </button>
              </div>

              <%!-- Desktop navigation --%>
              <nav class="hidden xl:block">
                <ul class="flex gap-3">
                  <li :for={{url, name} <- @nav}>
                    <.link
                      class="text-base-content whitespace-nowrap text-sm hover:underline hover:underline-offset-2"
                      navigate={url}
                    >
                      {name}
                    </.link>
                  </li>
                </ul>
              </nav>
            </div>

            <%!-- Centre --%>
            <div class="flex flex-1 flex-col items-center">
              <%!-- Logo --%>
              <.link
                navigate={~p"/"}
                class="text-primary font-sans whitespace-nowrap text-xl font-bold uppercase tracking-widest sm:text-2xl"
              >
                Eden Flowers
              </.link>
            </div>

            <%!-- Right --%>
            <div class="flex flex-1 items-center justify-end sm:gap-4">
              <%!-- Locale picker button --%>
              <.live_component id="locale-picker-header" module={EdenflowersWeb.LocalePicker}>
                <button class="group h-12 w-12 cursor-pointer sm:h-auto sm:w-auto">
                  <.icon name="hero-globe-alt" class="text-base-content h-5 w-5 group-hover:text-base-content/60" />
                  <span class="text-base-content hidden text-sm group-hover:text-base-content/60 sm:inline-flex">
                    {@current_locale}
                  </span>
                </button>
              </.live_component>

              <%!-- Cart button --%>
              <button
                phx-click={JS.exec("phx-show", to: "#cart-drawer")}
                type="button"
                class="group h-12 w-12 cursor-pointer sm:h-auto sm:w-auto"
              >
                <.icon class="text-base-content h-5 w-5 group-hover:text-base-content/60" name="hero-shopping-bag" />
                <span class="text-base-content hidden text-sm group-hover:text-base-content/60 sm:inline-flex">
                  <%= if not is_nil(@order.total_items_in_cart) do %>
                    {gettext("Cart")} ({@order.total_items_in_cart})
                  <% else %>
                    {gettext("Cart")}
                  <% end %>
                </span>
              </button>
            </div>
          </div>
        </section>
      </header>
    </hotfx-shy-header>

    <main class="flex-grow">
      <.alert_group />
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </main>

    <footer>
      <div class="border-t border-b bg-pink-100">
        <div class="container py-12 md:py-24">
          <div class="flex flex-col gap-8 md:flex-row">
            <div class="m-auto flex-1">
              <div class="m-auto max-w-lg space-y-4">
                <h2 class="font-serif text-2xl sm:text-3xl">
                  {gettext("Enjoy 20% off your next order and get occassional floral advice in your inbox.")}
                </h2>

                <.form for={to_form(%{})}>
                  <input type="text" class="input input-lg w-full text-sm" placeholder="Email Address" name="email_address" />
                </.form>
              </div>
            </div>

            <div class="flex-1">
              <div class="m-auto max-w-lg">
                <.social_media_links size={6} />
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="flex flex-col items-center gap-4 py-8">
        <.live_component id="locale-picker-footer" module={EdenflowersWeb.LocalePicker}>
          <button class="group cursor-pointer">
            <.icon name="hero-globe-alt" class="text-base-content h-5 w-5 group-hover:text-base-content/60" />
            <span class="text-base-content inline-flex text-sm group-hover:text-base-content/60">
              {@current_locale}
            </span>
          </button>
        </.live_component>

        <span class="text-xs">
          © Eden Flowers {DateTime.now!("Europe/Helsinki") |> Map.get(:year)} •
          <a
            class="text-base-content whitespace-nowrap hover:underline hover:underline-offset-2"
            href="https://github.com/davemccrea/edenflowers_store"
          >
            {gettext("Built with ")} <span>❤️</span>
          </a>
        </span>
      </div>
    </footer>
    """
  end
end
