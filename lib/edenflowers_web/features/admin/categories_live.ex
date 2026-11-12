defmodule EdenflowersWeb.Admin.CategoriesLive do
  @moduledoc """
  Admin page for publishing, hiding and ordering the store's product categories.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Catalog
  alias Edenflowers.Events
  alias Edenflowers.Translations
  alias EdenflowersWeb.Admin.PubSub
  alias EdenflowersWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: PubSub.subscribe([Events.admin_product_categories()])

    {:ok, socket |> assign(:page_title, ~t"Categories") |> load_categories()}
  end

  @impl true
  def handle_event("set_visibility", %{"id" => id, "visibility" => visibility}, socket) do
    socket.assigns.categories
    |> Enum.find(&(&1.id == id))
    |> Catalog.set_category_visibility(visibility, actor: socket.assigns.current_user)
    |> saved(socket)
  end

  def handle_event("move", %{"id" => id, "direction" => direction}, socket) do
    socket.assigns.categories
    |> Enum.find(&(&1.id == id))
    |> Catalog.move_category(direction, actor: socket.assigns.current_user)
    |> saved(socket)
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{}, socket), do: {:noreply, PubSub.schedule_refresh(socket, :categories)}
  def handle_info({:admin_refresh, :categories}, socket), do: {:noreply, load_categories(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp saved({:ok, _category}, socket), do: {:noreply, load_categories(socket)}

  defp saved({:error, _error}, socket),
    do: {:noreply, socket |> put_flash(:error, ~t"Couldn't save the category. Try again.") |> load_categories()}

  defp load_categories(socket) do
    categories = Catalog.list_all_categories!(actor: socket.assigns.current_user)

    socket
    |> assign(:categories, Translations.translate(categories))
    # The product list filters on the stored name, which translating replaces.
    |> assign(:filter_names, Map.new(categories, &{&1.id, &1.name}))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={~t"Categories"} back={{~t"Products", ~p"/admin/products"}}>
          <:subtitle>{~t"The order here is the order of the categories in the store."}</:subtitle>
        </.admin_page_header>

        <ol id="categories" class="admin-card divide-base-content/8 max-w-3xl divide-y">
          <li
            :for={{category, index} <- Enum.with_index(@categories)}
            id={"category-#{category.id}"}
            class="flex flex-wrap items-center gap-x-4 gap-y-2 px-4 py-3"
          >
            <div class="flex shrink-0 gap-1 pointer-coarse:gap-3">
              <button
                type="button"
                class="btn btn-ghost btn-sm btn-square touch-target"
                phx-click="move"
                phx-value-id={category.id}
                phx-value-direction="up"
                disabled={index == 0}
                aria-label={~t"Move #{name = category.name} up"}
              >
                <.icon name="hero-chevron-up" class="h-4 w-4" />
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-sm btn-square touch-target"
                phx-click="move"
                phx-value-id={category.id}
                phx-value-direction="down"
                disabled={index == length(@categories) - 1}
                aria-label={~t"Move #{name = category.name} down"}
              >
                <.icon name="hero-chevron-down" class="h-4 w-4" />
              </button>
            </div>

            <div class="min-w-0 flex-1">
              <.link
                navigate={~p"/admin/products?#{%{"product_category.name" => @filter_names[category.id]}}"}
                class={["block truncate font-semibold hover:underline", category.visibility != :public && "text-base-content/50"]}
              >
                {category.name}
              </.link>
              <p class="text-base-content/60 text-xs">
                {dngettext(
                  "admin",
                  "%{count} published product",
                  "%{count} published products",
                  category.published_product_count
                )}
              </p>
            </div>

            <div class="flex gap-1 max-sm:basis-full" role="group" aria-label={~t"Visibility of #{name = category.name}"}>
              <button
                :for={visibility <- [:public, :hidden, :draft]}
                type="button"
                class={["btn btn-sm rounded-full font-normal shadow-none", if(category.visibility == visibility, do: "btn-primary", else: "btn-ghost")]}
                phx-click="set_visibility"
                phx-value-id={category.id}
                phx-value-visibility={visibility}
                aria-pressed={to_string(category.visibility == visibility)}
                data-confirm={draft_confirmation(category, visibility)}
              >
                {visibility_label(visibility)}
              </button>
            </div>
          </li>
        </ol>

        <dl class="text-base-content/75 mt-6 max-w-3xl space-y-2 text-sm leading-relaxed">
          <div :for={visibility <- [:public, :hidden, :draft]}>
            <dt class="text-base-content inline font-semibold">{visibility_label(visibility)}:</dt>
            <dd class="inline">{visibility_help(visibility)}</dd>
          </div>
        </dl>
      </.admin_page>
    </Layouts.admin>
    """
  end

  defp visibility_label(:public), do: ~t"Public"
  defp visibility_label(:hidden), do: ~t"Hidden"
  defp visibility_label(:draft), do: ~t"Draft"

  defp visibility_help(:public), do: ~t"Shown in the store."
  defp visibility_help(:hidden), do: ~t"Not in the store, but its products can still be bought, like cards at checkout."
  defp visibility_help(:draft), do: ~t"Not in the store, and its products can't be bought."

  defp draft_confirmation(%{visibility: visibility, published_product_count: count} = category, :draft)
       when visibility != :draft and count > 0 do
    dngettext(
      "admin",
      "Make %{name} a draft? Its %{count} published product will leave the store and checkout.",
      "Make %{name} a draft? Its %{count} published products will leave the store and checkout.",
      count,
      name: category.name
    )
  end

  defp draft_confirmation(_category, _visibility), do: nil
end
