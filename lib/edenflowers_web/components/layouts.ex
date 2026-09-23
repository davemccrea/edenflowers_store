defmodule EdenflowersWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use EdenflowersWeb, :html

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
  attr :class, :any, default: nil
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
      class={["cursor-pointer bg-transparent p-0", @class]}
    >
      {render_slot(@inner_block)}
    </button>
    <ul
      id={@id}
      popover
      style={"position-anchor: #{@anchor_name}; position-area: #{@position_area};"}
      class="dropdown menu bg-base-100 border-base-300 border p-1 shadow"
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
    case EdenflowersWeb.Auth.ReturnTo.safe_path(current_path) do
      nil -> ~p"/sign-in"
      "/" -> ~p"/sign-in"
      path -> ~p"/sign-in?return_to=#{path}"
    end
  end

  @doc """
  Renders the page's flash notices plus the connection-lost toasts, which
  LiveView reveals on disconnect and hides again on reconnect.
  """
  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div id="flash-group" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={~t"Connection lost"}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {~t"Reconnecting…"}
        <.icon name="hero-arrow-path" class="size-3 align-[-0.125em] ml-1 motion-safe:animate-spin" />
      </.flash>
      <.flash
        id="server-error"
        kind={:error}
        title={~t"Something went wrong"}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {~t"Reconnecting…"}
        <.icon name="hero-arrow-path" class="size-3 align-[-0.125em] ml-1 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  attr :flash, :map, required: true
  attr :current_path, :string, required: true
  slot :inner_block, required: true

  def auth(assigns) do
    current_locale = Localize.Language.display_name!(Localize.get_locale().language, fallback: true)

    assigns =
      assigns
      |> assign(current_locale: String.capitalize(current_locale))

    ~H"""
    <.flash_group flash={@flash} />

    <div class="bg-base-200 flex min-h-screen flex-col">
      <header class="py-8 text-center">
        <.link navigate={~p"/"} class="text-primary logo-wordmark text-xl sm:text-2xl">
          Eden Flowers
        </.link>
      </header>

      <main id="main-content" tabindex="-1" class="flex flex-grow items-center justify-center outline-hidden">
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

  attr :flash, :map, required: true
  attr :current_path, :string, required: true
  attr :current_user, :map, required: true
  slot :inner_block, required: true

  def admin(assigns) do
    current_locale =
      Localize.get_locale().language
      |> Localize.Language.display_name!(fallback: true)
      |> String.capitalize()

    primary_nav = [
      {"/admin", ~t"Dashboard", true, "hero-squares-2x2"},
      {EdenflowersWeb.Admin.OrdersLive.default_path(), ~t"Orders", true, "hero-shopping-bag"},
      {"/admin/expenses", ~t"Expenses", true, "hero-document-text"},
      {"/admin/fulfillments", ~t"Calendar", true, "hero-calendar-days"}
    ]

    system_nav = [
      {"/admin/errors", ~t"Errors", false, "hero-exclamation-triangle"},
      {"/admin/oban", "Oban", false, "hero-cpu-chip"},
      {"/admin/ash", "AshAdmin", false, "hero-circle-stack"}
    ]

    assigns =
      assigns
      |> assign(:current_locale, current_locale)
      |> assign(:primary_nav, primary_nav)
      |> assign(:system_nav, system_nav)

    ~H"""
    <.flash_group flash={@flash} />

    <div class="admin-theme min-h-screen lg:flex">
      <%!-- Mobile: slide-in drawer --%>
      <.drawer
        id="admin-nav-drawer"
        placement="left"
        label={~t"Admin navigation"}
        class="bg-base-200 border-base-content/12 flex h-full w-64 flex-col border-r"
      >
        <.admin_sidebar_content
          primary_nav={@primary_nav}
          system_nav={@system_nav}
          current_path={@current_path}
          current_locale={@current_locale}
          closeable={true}
        />
      </.drawer>

      <%!-- Desktop: persistent sidebar, pinned so it stays in view while content scrolls --%>
      <aside class="bg-base-200 border-base-content/12 hidden border-r lg:sticky lg:top-0 lg:flex lg:h-screen lg:w-64 lg:shrink-0 lg:flex-col">
        <.admin_sidebar_content
          primary_nav={@primary_nav}
          system_nav={@system_nav}
          current_path={@current_path}
          current_locale={@current_locale}
          closeable={false}
        />
      </aside>

      <div class="flex min-w-0 flex-1 flex-col">
        <%!-- Mobile topbar: hamburger pinned left, wordmark optically centered.
             The trailing spacer matches the button cell so the center column is
             truly centered on the bar, not on the leftover space. --%>
        <div class="grid-cols-[auto_1fr_auto] bg-base-200 border-base-content/12 grid items-center border-b px-2 py-2.5 lg:hidden">
          <button
            type="button"
            phx-click={JS.push_focus() |> JS.exec("phx-show", to: "#admin-nav-drawer")}
            aria-label={~t"Open navigation menu"}
            class="text-base-content/60 -m-px cursor-pointer p-2 transition-colors hover:text-base-content active:bg-base-300/50"
          >
            <.icon name="hero-bars-3" class="h-5 w-5" />
          </button>
          <.link
            href={~p"/"}
            class="text-primary logo-wordmark tracking-[0.12em] justify-self-center text-lg transition-colors active:text-primary/70"
          >
            Eden Flowers
          </.link>
          <.admin_account_menu current_user={@current_user} compact={true} />
        </div>

        <div class="border-base-content/12 hidden items-center justify-end border-b px-8 py-3 lg:flex">
          <.admin_account_menu current_user={@current_user} />
        </div>

        <main id="main-content" tabindex="-1" class="flex-grow pb-12 outline-hidden">
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>
    """
  end

  attr :primary_nav, :list, required: true
  attr :system_nav, :list, required: true
  attr :current_path, :string, required: true
  attr :current_locale, :string, required: true
  attr :closeable, :boolean, required: true

  defp admin_sidebar_content(assigns) do
    assigns =
      assign(
        assigns,
        :locale_picker_id,
        if(assigns.closeable, do: "admin-locale-picker-mobile", else: "admin-locale-picker-desktop")
      )

    ~H"""
    <div class="flex h-full flex-col py-5">
      <div class="mb-6 flex items-center justify-between px-5">
        <.link href={~p"/"} class="text-primary logo-wordmark text-lg">
          Eden Flowers
        </.link>
        <button
          :if={@closeable}
          type="button"
          phx-click={JS.exec("phx-hide", to: "#admin-nav-drawer")}
          aria-label={~t"Close navigation menu"}
          class="cursor-pointer"
        >
          <.icon name="hero-x-mark" class="text-base-content/60 h-5 w-5 hover:text-base-content/80" />
        </button>
      </div>

      <nav class="min-h-0 flex-1 space-y-0.5 overflow-y-auto px-3">
        <.admin_nav_item
          :for={{path, label, live?, icon} <- @primary_nav}
          path={path}
          label={label}
          live?={live?}
          icon={icon}
          current_path={@current_path}
          exact={path == "/admin"}
        />
      </nav>

      <div class="border-base-content/12 mt-auto border-t px-3 pt-4">
        <.locale_picker id={@locale_picker_id} current_path={@current_path} class="mb-3 w-full">
          <span class="text-base-content/65 flex items-center gap-3 border-l-2 border-transparent px-3 py-2 text-sm transition-colors hover:bg-base-300/40 hover:text-base-content">
            <.icon name="hero-globe-alt" class="text-base-content/60 h-4 w-4 shrink-0" />
            <span class="flex-1 text-left">{@current_locale}</span>
            <.icon name="hero-chevron-up-down" class="text-base-content/60 h-4 w-4 shrink-0" />
          </span>
        </.locale_picker>

        <p class="text-base-content/65 mb-1 px-3 text-xs">{~t"System"}</p>
        <.admin_nav_item
          :for={{path, label, live?, icon} <- @system_nav}
          path={path}
          label={label}
          live?={live?}
          icon={icon}
          current_path={@current_path}
          exact={false}
        />
      </div>
    </div>
    """
  end

  attr :path, :string, required: true
  attr :label, :string, required: true
  attr :live?, :boolean, required: true
  attr :icon, :string, required: true
  attr :current_path, :string, required: true
  attr :exact, :boolean, default: false

  defp admin_nav_item(assigns) do
    assigns =
      assign(assigns, :active, admin_nav_active?(assigns.current_path, assigns.path, assigns.exact))

    ~H"""
    <.link
      {if @live?, do: [navigate: @path], else: [href: @path]}
      aria-current={@active && "page"}
      class={["flex items-center gap-3 px-3 py-2 text-sm transition-colors", if(@active,
    do: "border-primary text-base-content bg-base-300/50 border-l-2 font-medium",
    else: "text-base-content/65 border-l-2 border-transparent hover:bg-base-300/40 hover:text-base-content")]}
    >
      <.icon name={@icon} class={["h-4 w-4 shrink-0", if(@active, do: "text-primary", else: "text-base-content/60")]} />
      {@label}
    </.link>
    """
  end

  defp admin_nav_active?(current_path, path, exact) do
    # Nav paths may carry default filters in their query string; only the path decides the active item.
    nav_path = URI.parse(path).path

    if exact, do: current_path == nav_path, else: String.starts_with?(current_path, nav_path)
  end

  attr :current_user, :map, required: true
  attr :compact, :boolean, default: false

  defp admin_account_menu(assigns) do
    assigns =
      assigns
      |> assign(:display_name, admin_user_display_name(assigns.current_user))
      |> assign(:email, admin_user_email(assigns.current_user))
      |> assign(:initials, admin_user_initials(assigns.current_user))

    ~H"""
    <div class="dropdown dropdown-end">
      <button
        type="button"
        tabindex="0"
        aria-label={~t"Admin account menu"}
        class={["inline-flex cursor-pointer items-center transition-colors hover:bg-base-300/50 focus-visible:outline-solid focus-visible:outline-2 focus-visible:outline-offset-2", if(@compact, do: "h-9 w-9 justify-center p-0", else: "gap-2 px-2 py-1.5")]}
      >
        <img
          :if={@current_user.avatar_content_type}
          src={~p"/admin/account/avatar"}
          alt=""
          class="h-7 w-7 shrink-0 rounded-full object-cover"
        />
        <span
          :if={!@current_user.avatar_content_type}
          class="bg-primary/10 text-primary inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-xs font-semibold"
        >
          {@initials}
        </span>
        <span :if={!@compact} class="min-w-0 text-left">
          <span class="text-base-content max-w-44 block truncate text-sm font-medium">{@display_name}</span>
          <span class="text-base-content/65 max-w-44 block truncate text-xs">{@email}</span>
        </span>
        <.icon :if={!@compact} name="hero-chevron-down" class="text-base-content/60 h-4 w-4 shrink-0" />
      </button>

      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-100 border-base-300 mt-2 w-56 border p-1 shadow"
      >
        <li :if={@compact} class="px-3 py-2">
          <span class="block p-0 hover:bg-transparent">
            <span class="text-base-content block truncate text-sm font-medium">{@display_name}</span>
            <span class="text-base-content/65 block truncate text-xs">{@email}</span>
          </span>
        </li>
        <li :if={@compact}></li>
        <li>
          <.link navigate={~p"/admin/account"}>
            <.icon name="hero-user-circle" class="h-4 w-4" />
            {~t"Account"}
          </.link>
        </li>
        <li>
          <.link href={~p"/sign-out"} method="delete">
            <.icon name="hero-arrow-right-start-on-rectangle" class="h-4 w-4" />
            {~t"Sign out"}
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  defp admin_user_display_name(user) do
    user
    |> Map.get(:first_name)
    |> case do
      first_name when is_binary(first_name) ->
        first_name = String.trim(first_name)
        if first_name == "", do: admin_user_email(user), else: first_name

      _ ->
        admin_user_email(user)
    end
  end

  defp admin_user_email(user), do: user |> Map.get(:email) |> to_string()

  defp admin_user_initials(user) do
    user
    |> Map.get(:initials)
    |> case do
      initials when is_binary(initials) ->
        initials = String.trim(initials)
        if initials == "", do: fallback_admin_initial(user), else: initials

      _ ->
        fallback_admin_initial(user)
    end
  end

  defp fallback_admin_initial(user),
    do: user |> admin_user_email() |> String.first() |> Kernel.||("A") |> String.upcase()

  attr :current_user, :map, required: true
  attr :flash, :map, required: true
  attr :order, :map, required: true
  attr :current_path, :string, required: true
  slot :inner_block, required: true

  def app(assigns) do
    current_locale_code = Edenflowers.Format.locale()
    current_locale = Localize.Language.display_name!(Localize.get_locale().language, fallback: true)

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
                class="font-serif text-base-content link-underline-hover text-3xl"
                phx-click={JS.exec("phx-hide", to: "#nav-drawer")}
                navigate={url}
              >
                {name}
              </.link>
            </li>
          </ul>
        </nav>
      </div>

      <footer class="bg-base-300 flex flex-col gap-6 px-8 py-8">
        <.link
          class="text-base-content link-underline-hover w-fit text-sm tracking-wide"
          phx-click={JS.exec("phx-hide", to: "#nav-drawer")}
          navigate={if @current_user, do: ~p"/account"}
          href={unless @current_user, do: sign_in_href(@current_path)}
        >
          {if @current_user, do: ~t"Account", else: ~t"Sign In"}
        </.link>

        <.locale_list
          locales={@locales}
          current_locale_code={@current_locale_code}
          current_path={@current_path}
          class="flex flex-wrap gap-x-5 gap-y-2"
          item_class="text-base-content/80 link-underline-hover text-sm tracking-wide"
        />
        <.social_media_links />
      </footer>
    </.drawer>

    <.live_component
      id="cart-drawer-component"
      module={EdenflowersWeb.Cart.Drawer}
      order={@order}
      current_user={@current_user}
    />

    <div
      id="hotfx-shy-header"
      phx-hook="HotFxShyHeader"
      data-hide={JS.add_class("shy-header--hidden")}
      data-show={JS.remove_class("shy-header--hidden")}
    >
      <header class="w-full">
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
                      class="text-base-content link-underline-hover whitespace-nowrap text-sm tracking-wide"
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
                class="text-primary logo-wordmark whitespace-nowrap text-2xl max-sm:tracking-[0.14em] lg:text-3xl"
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
                count={@order.total_items_in_cart}
                phx-click={JS.push_focus() |> JS.exec("phx-show", to: "#cart-drawer")}
              >
                <.icon
                  class="text-base-content h-5 w-5 group-hover:text-base-content/60"
                  name="hero-shopping-bag"
                />
                <%= if @order.total_items_in_cart > 0 do %>
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
                  <%= if @order.total_items_in_cart > 0 do %>
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

    <.flash_group flash={@flash} />

    <main id="main-content" tabindex="-1" class="flex-grow outline-hidden">
      {render_slot(@inner_block)}
    </main>

    <.link
      :if={@current_user && @current_user.admin}
      id="admin-shortcut"
      navigate={~p"/admin"}
      class="bg-base-content text-base-100 fixed bottom-6 left-1/2 z-40 inline-flex -translate-x-1/2 items-center gap-2 rounded-full px-5 py-2.5 text-sm font-medium shadow-lg hover:opacity-90"
    >
      <.icon name="hero-document-text" class="h-5 w-5" />
      {~t"Admin"}
    </.link>

    <footer>
      <div class="bg-cream relative overflow-hidden border-t border-b">
        <.flower
          name="flower-41"
          class="text-base-content/15 pointer-events-none absolute top-6 right-6 h-20 w-20 md:top-10 md:right-10 md:h-28 md:w-28"
        />
        <div class="container relative py-20 md:py-36">
          <div class="footer-grid">
            <div id="newsletter" class="footer-grid__newsletter space-y-4">
              <.live_component id="newsletter-signup-form" module={EdenflowersWeb.NewsletterSignup} />
            </div>

            <div class="footer-grid__location space-y-2">
              <h3 class="eyebrow text-base-content/70">{~t"Address"}</h3>
              <a
                href="https://www.google.com/maps/search/?api=1&amp;query=Minimossen%2C+Myrv%C3%A4gen+1%2C+65230+Vasa"
                target="_blank"
                rel="noopener noreferrer"
                class="link-underline-static-body block space-y-2"
              >
                <p class="footer-line whitespace-nowrap">Minimossen</p>
                <p class="footer-line whitespace-nowrap">{~t"Myrvägen 1"}</p>
                <p class="footer-line whitespace-nowrap">{~t"65230 Vasa"}</p>
              </a>
            </div>

            <div class="footer-grid__hours space-y-2">
              <h3 class="eyebrow text-base-content/70">
                {~t"Opening hours"}
              </h3>
              <div class="space-y-1">
                <p class="footer-line whitespace-nowrap">{~t"Mon–Fri: 09:00–17:00"}</p>
                <p class="footer-line whitespace-nowrap">{~t"Sat: 10:00–15:00"}</p>
                <p class="footer-line whitespace-nowrap">{~t"Sun: closed"}</p>
              </div>
            </div>

            <div class="footer-grid__help space-y-2">
              <h3 class="eyebrow text-base-content/70">{~t"Help"}</h3>
              <ul class="space-y-1">
                <li>
                  <.link navigate={~p"/faq"} class="footer-line link-underline-hover">
                    {~t"FAQ"}
                  </.link>
                </li>
                <li>
                  <.link navigate={~p"/contact"} class="footer-line link-underline-hover">
                    {~t"Contact"}
                  </.link>
                </li>
                <li>
                  <.link navigate={~p"/about"} class="footer-line link-underline-hover">
                    {~t"About"}
                  </.link>
                </li>
              </ul>
            </div>

            <div class="footer-grid__socials space-y-2">
              <h3 class="eyebrow text-base-content/70">{~t"Socials"}</h3>
              <.social_media_links />
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
            © Eden Flowers {DateTime.now!("Europe/Helsinki") |> Map.get(:year)} • Y-tunnus:
            <a
              class="text-base-content link-underline-hover whitespace-nowrap"
              href="https://tietopalvelu.ytj.fi/yritys/2944459-6"
              target="_blank"
              rel="noopener"
            >
              2944459-6
            </a>
            •
            <a
              class="text-base-content link-underline-hover whitespace-nowrap"
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
