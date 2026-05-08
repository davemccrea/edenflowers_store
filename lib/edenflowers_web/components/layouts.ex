defmodule EdenflowersWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use EdenflowersWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  attr :id, :string, required: true
  attr :current_path, :string, required: true
  attr :placement, :string, default: "top", values: ~w(top bottom)
  slot :inner_block, required: true

  def locale_picker(assigns) do
    locales =
      for code <- Edenflowers.Locales.all() do
        language_code = code |> String.split("-") |> hd()
        name = Localize.Language.display_name!(language_code, locale: code, fallback: true)
        {code, String.capitalize(name)}
      end

    assigns = assign(assigns, :locales, locales)

    ~H"""
    <details id={@id} class={["dropdown dropdown-end", "dropdown-#{@placement}"]}>
      <summary class="cursor-pointer list-none">
        {render_slot(@inner_block)}
      </summary>
      <ul class="dropdown-content menu bg-base-100 border-base-300 z-10 mt-1 rounded-none border p-1 shadow">
        <li :for={{code, name} <- @locales}>
          <.link href={~p"/locale/#{code}?redirect_to=#{@current_path}"}>
            {name}
          </.link>
        </li>
      </ul>
    </details>
    """
  end

  attr :flash, :map, required: true
  attr :current_path, :string, required: true
  slot :inner_block, required: true

  def auth(assigns) do
    {:ok, current_locale} = Localize.Language.display_name(Localize.get_locale())

    assigns =
      assigns
      |> assign(current_locale: String.capitalize(current_locale))

    ~H"""
    <div class="auth-background-pattern flex min-h-screen flex-col">
      <header class="py-8 text-center">
        <.link navigate={~p"/"} class="text-primary logo-wordmark text-xl sm:text-2xl">
          Eden Flowers
        </.link>
      </header>

      <main class="flex flex-grow items-center justify-center">
        <.alert_group />
        <.flash_group flash={@flash} />
        {render_slot(@inner_block)}
      </main>

      <footer class="py-8 text-center">
        <.locale_picker id="locale-picker-footer" current_path={@current_path}>
          <span class="group inline-flex cursor-pointer items-center gap-1">
            <.icon name="hero-globe-alt" class="text-base-content h-5 w-5 group-hover:text-base-content/60" />
            <span class="text-base-content inline-flex text-sm group-hover:text-base-content/60">
              {@current_locale}
            </span>
          </span>
        </.locale_picker>
      </footer>
    </div>
    """
  end

  attr :current_user, :map, required: true
  attr :flash, :map, required: true
  attr :order, :map, required: true
  attr :current_path, :string, required: true
  slot :inner_block, required: true

  def app(assigns) do
    {:ok, current_locale} = Localize.Language.display_name(Localize.get_locale())

    assigns =
      assigns
      |> assign(
        nav: [
          {~p"/store/bouquets", ~t"Store"},
          {~p"/courses", ~t"Courses"},
          {~p"/weddings", ~t"Weddings"},
          {~p"/condolences", ~t"Condolences"},
          {~p"/about", ~t"About"},
          {~p"/contact", ~t"Contact"}
        ]
      )
      |> assign(current_locale: String.capitalize(current_locale))

    ~H"""
    <.drawer id="nav-drawer" placement="left" class="bg-base-200 border-r-1 w-[80vw] flex h-full flex-col sm:w-[25rem]">
      <header class="flex flex-row items-center justify-between pt-8 pr-4 pl-8">
        <.link
          navigate={~p"/"}
          class="text-primary logo-wordmark whitespace-nowrap sm:text-2xl"
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
                class="font-serif text-base-content text-3xl hover:decoration-(--color-accent-alt) hover:underline hover:underline-offset-4"
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
      <header class="flex flex-row items-center justify-between pt-8 pr-4 pl-8">
        <h1 class="section-title">
          <%= if not is_nil(@order.total_items_in_cart) do %>
            {~t"Cart"} ({@order.total_items_in_cart})
          <% else %>
            {~t"Cart"}
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
        <.button navigate={~p"/checkout"} variant="primary" phx-click={JS.exec("phx-hide", to: "#cart-drawer")}>
          {~t"Checkout"}
        </.button>
      </footer>
    </.drawer>

    <div
      id="hotfx-shy-header"
      phx-hook="HotFxShyHeader"
      data-hide={JS.add_class("hidden")}
      data-show={JS.remove_class("hidden")}
    >
      <header class="w-full">
        <%!-- Banner --%>
        <section class="bg-pastel-1 border-b py-2 text-center">
          <span class="text-accent-content text-sm">{~t"Let us know what you think of the new website! 🚀"}</span>
        </section>

        <%!-- Main header --%>
        <section class="bg-base-100 border-b px-3 py-2 sm:px-6 sm:py-4">
          <div class="flex items-center">
            <%!-- Left --%>
            <div class="flex flex-1 justify-start">
              <%!-- Mobile hamburger menu --%>
              <div class="block xl:hidden">
                <button
                  phx-click={JS.push_focus() |> JS.exec("phx-show", to: "#nav-drawer")}
                  type="button"
                  class="h-12 w-12 cursor-pointer"
                  aria-label={~t"Open navigation menu"}
                >
                  <.icon name="hero-bars-3-bottom-left" class="text-base-content h-6 w-6 hover:text-base-content/60" />
                </button>
              </div>

              <%!-- Desktop navigation --%>
              <nav class="hidden xl:block">
                <ul class="flex gap-6">
                  <li :for={{url, name} <- @nav}>
                    <.link
                      class="text-base-content underline-offset-[6px] whitespace-nowrap text-sm tracking-wide hover:decoration-(--color-accent-alt) hover:underline"
                      navigate={url}
                    >
                      {name}
                    </.link>
                  </li>
                </ul>
              </nav>
            </div>

            <%!-- Centre --%>
            <div class="flex flex-1 items-center justify-center">
              <%!-- Logo --%>
              <.link
                navigate={~p"/"}
                class="text-primary logo-wordmark whitespace-nowrap text-xl sm:text-2xl"
              >
                Eden Flowers
              </.link>
            </div>

            <%!-- Right --%>
            <div class="flex flex-1 items-center justify-end lg:gap-4">
              <%!-- Sign in --%>
              <.link
                navigate={if @current_user, do: ~p"/account", else: ~p"/sign-in"}
                class="group flex h-10 w-10 shrink-0 cursor-pointer items-center justify-center gap-1 lg:h-auto lg:w-auto lg:gap-2"
              >
                <.icon class="text-base-content h-5 w-5 group-hover:text-base-content/60" name="hero-user-circle" />
                <span class="text-base-content hidden whitespace-nowrap text-sm group-hover:text-base-content/60 lg:inline-flex">
                  {if @current_user,
                    do: ~t"Account",
                    else: ~t"Sign In"}
                </span>
              </.link>

              <%!-- Locale picker button --%>
              <.locale_picker id="locale-picker-header" placement="bottom" current_path={@current_path}>
                <span class="group flex h-10 w-10 cursor-pointer items-center justify-center gap-1 lg:h-auto lg:w-auto lg:gap-2">
                  <.icon name="hero-globe-alt" class="text-base-content h-5 w-5 group-hover:text-base-content/60" />
                  <span class="text-base-content hidden text-sm group-hover:text-base-content/60 lg:inline-flex">
                    {@current_locale}
                  </span>
                </span>
              </.locale_picker>

              <%!-- Cart button --%>
              <button
                phx-click={JS.push_focus() |> JS.exec("phx-show", to: "#cart-drawer")}
                type="button"
                class="group relative flex h-10 w-10 cursor-pointer items-center justify-center gap-1 lg:h-auto lg:w-auto lg:gap-2"
              >
                <.icon class="text-base-content h-5 w-5 group-hover:text-base-content/60" name="hero-shopping-bag" />

                <%= if not is_nil(@order.total_items_in_cart) && @order.total_items_in_cart > 0 do %>
                  <span class="absolute top-0 right-0 lg:hidden">
                    <div class="bg-primary text-primary-content border-base-100 h-5 w-5 text-[10px] inline-flex items-center justify-center rounded-full border-2 font-semibold leading-none">
                      {@order.total_items_in_cart}
                    </div>
                  </span>
                <% end %>

                <span class="text-base-content hidden text-sm group-hover:text-base-content/60 lg:inline-flex">
                  <%= if not is_nil(@order.total_items_in_cart) do %>
                    {~t"Cart"} ({@order.total_items_in_cart})
                  <% else %>
                    {~t"Cart"}
                  <% end %>
                </span>
              </button>
            </div>
          </div>
        </section>
      </header>
    </div>

    <main class="flex-grow">
      <.alert_group />
      <.flash_group flash={@flash} />

      {render_slot(@inner_block)}
    </main>

    <footer>
      <div class="bg-accent border-t border-b">
        <div class="container py-20 md:py-36">
          <div class="footer-grid">
            <div class="footer-grid__newsletter space-y-4">
              <.live_component id="newsletter-signup-form" module={EdenflowersWeb.NewsletterSignupForm} />
            </div>

            <div class="footer-grid__location space-y-2">
              <h3 class="eyebrow text-base-content/60">Minimosen</h3>
              <p class="footer-line whitespace-nowrap">Kauppapuistikko 21</p>
              <p class="footer-line whitespace-nowrap">65100 Vaasa</p>
            </div>

            <div class="footer-grid__hours space-y-2">
              <h3 class="eyebrow text-base-content/60">
                {~t"Opening hours"}
              </h3>
              <div class="space-y-1">
                <p class="footer-line whitespace-nowrap">Ma–Pe: 09:00–17:00</p>
                <p class="footer-line whitespace-nowrap">La: 10:00–15:00</p>
                <p class="footer-line whitespace-nowrap">Su: suljettu</p>
              </div>
            </div>

            <div class="footer-grid__socials space-y-2">
              <h3 class="eyebrow text-base-content/60">{~t"Socials"}</h3>
              <.social_media_links size={6} />
            </div>
          </div>
        </div>
      </div>

      <div class="flex flex-col items-center gap-4 py-8">
        <.locale_picker id="locale-picker-footer" current_path={@current_path}>
          <span class="group inline-flex cursor-pointer items-center gap-1">
            <.icon name="hero-globe-alt" class="text-base-content h-5 w-5 group-hover:text-base-content/60" />
            <span class="text-base-content inline-flex text-sm group-hover:text-base-content/60">
              {@current_locale}
            </span>
          </span>
        </.locale_picker>

        <span class="text-xs">
          © Eden Flowers {DateTime.now!("Europe/Helsinki") |> Map.get(:year)} •
          <a
            class="text-base-content whitespace-nowrap hover:underline hover:underline-offset-2"
            href="https://github.com/davemccrea/edenflowers_store"
          >
            {~t"Built with "} <span>❤️</span>
          </a>
        </span>
      </div>
    </footer>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card border-base-300 bg-base-300 relative flex flex-row items-center rounded-full border-2">
      <div class="border-1 border-base-200 bg-base-100 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left] absolute left-0 h-full w-1/3 rounded-full brightness-200" />

      <button class="flex w-1/3 cursor-pointer p-2" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="system">
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button class="flex w-1/3 cursor-pointer p-2" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="light">
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button class="flex w-1/3 cursor-pointer p-2" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="dark">
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
