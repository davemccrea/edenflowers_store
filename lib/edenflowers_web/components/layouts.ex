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

  @doc """
  Renders the locale switcher as a single source of truth for header,
  drawer, and footer. Uses `aria-current="true"` on the active locale so
  AT users hear which language they're on.
  """
  attr :locales, :list, required: true, doc: "list of {code, name} tuples"
  attr :current_locale_code, :string, required: true
  attr :current_path, :string, required: true
  attr :class, :any, default: nil
  attr :item_class, :any, default: nil

  def locale_list(assigns) do
    ~H"""
    <ul class={@class}>
      <li :for={{code, name} <- @locales}>
        <.link
          href={~p"/locale/#{code}?redirect_to=#{@current_path}"}
          class={[@item_class, code == @current_locale_code && "text-base-content font-semibold"]}
          aria-current={code == @current_locale_code && "true"}
        >
          {name}
        </.link>
      </li>
    </ul>
    """
  end

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

    position_area =
      case assigns.placement do
        "bottom" -> "bottom span-left"
        "top" -> "top span-left"
      end

    assigns =
      assigns
      |> assign(:locales, locales)
      |> assign(:anchor_name, "--#{assigns.id}")
      |> assign(:position_area, position_area)

    ~H"""
    <button
      type="button"
      popovertarget={@id}
      style={"anchor-name: #{@anchor_name}"}
      class="cursor-pointer bg-transparent p-0"
    >
      {render_slot(@inner_block)}
    </button>
    <ul
      id={@id}
      popover
      style={"position-anchor: #{@anchor_name}; position-area: #{@position_area};"}
      class="dropdown menu bg-base-100 border-base-300 rounded-none border p-1 shadow"
    >
      <li :for={{code, name} <- @locales}>
        <.link href={~p"/locale/#{code}?redirect_to=#{@current_path}"}>
          {name}
        </.link>
      </li>
    </ul>
    """
  end

  # Builds a sign-in href, attaching the current path as a `return_to` so the
  # user lands back where they started. Filters out paths that aren't worth
  # capturing (the sign-in page itself, the home page, anything not safe).
  defp sign_in_href(current_path) do
    case EdenflowersWeb.ReturnTo.safe_path(current_path) do
      nil -> ~p"/sign-in"
      "/" -> ~p"/sign-in"
      path -> ~p"/sign-in?return_to=#{path}"
    end
  end

  attr :flash, :map, required: true
  attr :current_path, :string, required: true
  slot :inner_block, required: true

  def auth(assigns) do
    current_locale = Localize.Language.display_name!(Localize.get_locale(), fallback: true)

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

      <main id="main-content" tabindex="-1" class="flex flex-grow items-center justify-center outline-hidden">
        <.flash kind={:info} flash={@flash} />
        <.flash kind={:error} flash={@flash} />
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
    current_locale_code = Localize.get_locale().cldr_locale_id |> to_string()
    current_locale = Localize.Language.display_name!(Localize.get_locale(), fallback: true)

    locales =
      for code <- Edenflowers.Locales.all() do
        language_code = code |> String.split("-") |> hd()
        name = Localize.Language.display_name!(language_code, locale: code, fallback: true)
        {code, String.capitalize(name)}
      end

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
      |> assign(current_locale_code: current_locale_code)
      |> assign(locales: locales)

    ~H"""
    <.drawer
      id="nav-drawer"
      placement="left"
      label="Navigation menu"
      class="bg-base-200 border-r-1 w-[80vw] flex h-full flex-col sm:w-[25rem]"
    >
      <header class="flex flex-row items-center justify-between pt-8 pr-4 pl-8">
        <.link
          navigate={~p"/"}
          class="text-primary logo-wordmark whitespace-nowrap text-xl sm:text-3xl"
        >
          Eden Flowers
        </.link>

        <.icon_button aria_label={~t"Close navigation menu"} phx-click={JS.exec("phx-hide", to: "#nav-drawer")}>
          <.icon name="hero-x-mark" class="h-6 w-6 hover:text-base-content/60" />
        </.icon_button>
      </header>

      <div class="flex flex-1 flex-col justify-between p-8">
        <nav>
          <ul class="space-y-4">
            <li :for={{url, name} <- @nav}>
              <.link
                class="font-serif text-base-content link-underline-hover-display text-3xl"
                phx-click={JS.exec("phx-hide", to: "#nav-drawer")}
                navigate={url}
              >
                {name}
              </.link>
            </li>
            <li class="border-base-content/10 border-t pt-4">
              <.link
                class="text-base-content group font-serif inline-flex items-center gap-3 text-3xl hover:decoration-(--color-link-underline) hover:underline hover:underline-offset-4"
                phx-click={JS.exec("phx-hide", to: "#nav-drawer")}
                navigate={if @current_user, do: ~p"/account"}
                href={unless @current_user, do: sign_in_href(@current_path)}
              >
                <.icon name="hero-user-circle" class="h-7 w-7" />
                {if @current_user, do: ~t"Account", else: ~t"Sign In"}
              </.link>
            </li>
          </ul>
        </nav>
      </div>

      <footer class="bg-base-300 flex flex-col gap-6 px-8 py-8">
        <.locale_list
          locales={@locales}
          current_locale_code={@current_locale_code}
          current_path={@current_path}
          class="flex flex-wrap gap-x-5 gap-y-2"
          item_class="text-base-content/80 text-sm tracking-wide hover:decoration-(--color-link-underline) hover:underline hover:underline-offset-4"
        />
        <.social_media_links size={6} />
      </footer>
    </.drawer>

    <.live_component
      id="cart-drawer-component"
      module={EdenflowersWeb.CartDrawerComponent}
      order={@order}
      current_user={@current_user}
    />

    <div
      id="hotfx-shy-header"
      phx-hook="HotFxShyHeader"
      data-hide={JS.add_class("hidden")}
      data-show={JS.remove_class("hidden")}
    >
      <header class="w-full">
        <%!-- Banner --%>
        <section class="bg-forest py-2 text-center">
          <span class="text-forest-content text-sm">{~t"Let us know what you think of the new website! 🚀"}</span>
        </section>

        <%!-- Main header --%>
        <section class="bg-base-100 border-b px-3 py-2 sm:px-6 sm:py-4">
          <div class="flex items-center">
            <%!-- Left --%>
            <div class="flex flex-1 justify-start">
              <%!-- Mobile hamburger menu --%>
              <div class="block xl:hidden">
                <.disclosure_trigger
                  aria_label={~t"Open navigation menu"}
                  controls="nav-drawer"
                  phx-click={JS.push_focus() |> JS.exec("phx-show", to: "#nav-drawer")}
                >
                  <.icon name="hero-bars-3-bottom-left" class="text-base-content h-6 w-6 hover:text-base-content/60" />
                </.disclosure_trigger>
              </div>

              <%!-- Desktop navigation --%>
              <nav class="hidden xl:block">
                <ul class="flex gap-6">
                  <li :for={{url, name} <- @nav}>
                    <.link
                      class="text-base-content link-underline-hover-nav whitespace-nowrap text-sm tracking-wide"
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
                class="text-primary logo-wordmark tracking-[0.14em] whitespace-nowrap text-2xl sm:tracking-[0.18em] sm:text-2xl lg:text-3xl"
              >
                Eden Flowers
              </.link>
            </div>

            <%!-- Right --%>
            <div class="flex flex-1 items-center justify-end lg:gap-4">
              <%!-- Sign in (desktop only — mobile lives in nav drawer) --%>
              <.link
                navigate={if @current_user, do: ~p"/account"}
                href={unless @current_user, do: sign_in_href(@current_path)}
                class="group hidden h-10 w-10 shrink-0 cursor-pointer items-center justify-center gap-1 xl:flex xl:h-auto xl:w-auto xl:gap-2"
              >
                <.icon class="text-base-content h-5 w-5 group-hover:text-base-content/60" name="hero-user-circle" />
                <span class="text-base-content hidden whitespace-nowrap text-sm group-hover:text-base-content/60 lg:inline-flex">
                  {if @current_user,
                    do: ~t"Account",
                    else: ~t"Sign In"}
                </span>
              </.link>

              <%!-- Locale picker (desktop only — mobile lives in nav drawer) --%>
              <div class="hidden xl:block">
                <.locale_picker id="locale-picker-header" placement="bottom" current_path={@current_path}>
                  <span class="group flex h-10 cursor-pointer items-center gap-2">
                    <.icon name="hero-globe-alt" class="text-base-content h-5 w-5 group-hover:text-base-content/60" />
                    <span class="text-base-content text-sm group-hover:text-base-content/60">
                      {@current_locale}
                    </span>
                  </span>
                </.locale_picker>
              </div>

              <%!-- Cart button --%>
              <.cart_count_badge
                count={@order.total_items_in_cart || 0}
                phx-click={JS.push_focus() |> JS.exec("phx-show", to: "#cart-drawer")}
              >
                <.icon
                  class="text-base-content h-5 w-5 group-hover:text-base-content/60"
                  name="hero-shopping-bag"
                />
                <%= if not is_nil(@order.total_items_in_cart) && @order.total_items_in_cart > 0 do %>
                  <span class="absolute top-0 right-0 lg:hidden" aria-hidden="true">
                    <div class="bg-primary text-primary-content border-base-100 text-[10px] inline-flex h-5 w-5 items-center justify-center rounded-full border-2 font-semibold leading-none">
                      {@order.total_items_in_cart}
                    </div>
                  </span>
                <% end %>
                <span
                  class="text-base-content hidden text-sm group-hover:text-base-content/60 lg:inline-flex"
                  aria-hidden="true"
                >
                  <%= if not is_nil(@order.total_items_in_cart) do %>
                    {~t"Cart"} ({@order.total_items_in_cart})
                  <% else %>
                    {~t"Cart"}
                  <% end %>
                </span>
              </.cart_count_badge>
            </div>
          </div>
        </section>
      </header>
    </div>

    <main id="main-content" tabindex="-1" class="flex-grow outline-hidden">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      {render_slot(@inner_block)}
    </main>

    <footer>
      <div class="bg-cream relative overflow-hidden border-t border-b">
        <.flower
          name="flower-41"
          class="text-base-content/15 pointer-events-none absolute top-6 right-6 h-20 w-20 md:top-10 md:right-10 md:h-28 md:w-28"
        />
        <div class="container relative py-20 md:py-36">
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

            <div class="footer-grid__help space-y-2">
              <h3 class="eyebrow text-base-content/60">{~t"Help"}</h3>
              <ul class="space-y-1">
                <li>
                  <.link navigate={~p"/faq"} class="footer-line link-underline-hover-nav">
                    {~t"FAQ"}
                  </.link>
                </li>
                <li>
                  <.link navigate={~p"/contact"} class="footer-line link-underline-hover-nav">
                    {~t"Contact"}
                  </.link>
                </li>
                <li>
                  <.link navigate={~p"/about"} class="footer-line link-underline-hover-nav">
                    {~t"About"}
                  </.link>
                </li>
              </ul>
            </div>

            <div class="footer-grid__socials space-y-2">
              <h3 class="eyebrow text-base-content/60">{~t"Socials"}</h3>
              <.social_media_links size={6} />
            </div>
          </div>
        </div>
      </div>

      <div class="container">
        <div class="flex flex-col items-center gap-3 py-6">
          <.locale_picker id="locale-picker-footer" current_path={@current_path}>
            <span class="group inline-flex cursor-pointer items-center gap-1">
              <.icon name="hero-globe-alt" class="text-base-content h-5 w-5 group-hover:text-base-content/60" />
              <span class="text-base-content inline-flex text-sm group-hover:text-base-content/60">
                {@current_locale}
              </span>
            </span>
          </.locale_picker>

          <span class="text-xs">
            © Eden Flowers {DateTime.now!("Europe/Helsinki") |> Map.get(:year)} • Y-tunnus: 2944459-6 •
            <a
              class="text-base-content link-underline-hover-nav whitespace-nowrap"
              href="https://github.com/davemccrea/edenflowers_store"
            >
              {~t"Built with "} <span>❤️</span>
            </a>
          </span>
        </div>
      </div>
    </footer>
    """
  end
end
