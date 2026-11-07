defmodule EdenflowersWeb.Cart.LineItems do
  @moduledoc """
  Interactive cart lines for changing quantities and removing items or the selected card.
  """

  use EdenflowersWeb, :live_component

  alias Edenflowers.Orders
  alias EdenflowersWeb.Checkout.Fields

  attr :id, :string, required: true
  attr :order, :any, required: true
  # Only the checkout has the card picker for the card line to open.
  attr :card_picker?, :boolean, default: false
  # Only the checkout has a form to type into; what's typed there isn't on the order until a step is submitted.
  attr :typed_details?, :boolean, default: false

  @impl true
  def mount(socket),
    do: {:ok, assign(socket, refused: %{}, card_picker?: false, asking_to_remove: nil, typed_details?: false)}

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <%= if @order != nil and Enum.any?(@order.line_items) do %>
        <ul class="flex flex-col gap-5">
          <li :for={line_item <- @order.line_items} class="flex flex-row gap-3 text-base sm:gap-4">
            <%= if not line_item.is_card do %>
              <.link
                navigate={~q"/#{language}/product/#{line_item.product_slug}"}
                class="shrink-0 transition-opacity hover:opacity-70"
              >
                <.image
                  src={line_item.product_image_slug}
                  alt={"Image of #{line_item.product_name}"}
                  width={80}
                  height={80}
                  sizes="80px"
                  loading="eager"
                  class="h-16 w-16 object-cover sm:h-20 sm:w-20"
                />
              </.link>
            <% else %>
              <%!-- The name below is the button screen readers and keyboards reach. Safari rings this one when the drawer hands focus back. --%>
              <button
                :if={@card_picker?}
                type="button"
                tabindex="-1"
                aria-hidden="true"
                phx-click={JS.exec("phx-show", to: "#card-drawer")}
                class="shrink-0 cursor-pointer outline-hidden transition-opacity hover:opacity-70"
              >
                <.card_image line_item={line_item} />
              </button>
              <.card_image :if={not @card_picker?} line_item={line_item} />
            <% end %>

            <div class="flex min-w-0 flex-1 flex-col gap-2">
              <div class="flex flex-row justify-between gap-3">
                <div class="flex min-w-0 flex-col gap-0.5 break-words">
                  <%= if not line_item.is_card do %>
                    <.link
                      navigate={~q"/#{language}/product/#{line_item.product_slug}"}
                      class="link-underline-hover"
                    >
                      {line_item.product_name}
                    </.link>
                  <% else %>
                    <button
                      :if={@card_picker?}
                      type="button"
                      phx-click={JS.exec("phx-show", to: "#card-drawer")}
                      aria-haspopup="dialog"
                      class="link-underline-hover cursor-pointer text-left"
                      data-testid="cart-change-card-button"
                    >
                      {Edenflowers.Format.line_item_name(line_item)}
                      <span class="sr-only">{gettext("Change card")}</span>
                    </button>
                    <span :if={not @card_picker?}>{Edenflowers.Format.line_item_name(line_item)}</span>
                  <% end %>
                  <span
                    :if={line_item.variant_size}
                    class="font-serif text-base-content/65 text-sm italic"
                    data-testid="line-item-meta"
                  >
                    {variant_size_label(line_item.variant_size)}
                  </span>
                </div>
                <span class="shrink-0 text-right tabular-nums">
                  {Edenflowers.Format.currency(line_item.subtotal, @order.locale)}
                  <span :if={line_item.interval_weeks} class="text-base-content/65 block text-sm">
                    {~t"per delivery"}
                  </span>
                </span>
              </div>

              <%!-- gap-2 and the 4rem mobile thumbnail are load-bearing: three 3rem
              buttons only fit on one line down to 320px with this budget. --%>
              <div :if={not line_item.is_card} class="text-base-content/70 flex flex-row items-center justify-between gap-2">
                <span
                  :if={line_item.interval_weeks}
                  class="inline-flex items-center gap-1.5 text-sm"
                  data-testid="line-item-interval"
                >
                  <.icon name="hero-arrow-path" class="h-4 w-4" />
                  {Fields.interval_label(line_item.interval_weeks)}
                </span>
                <div :if={is_nil(line_item.interval_weeks)} class="flex flex-row items-center gap-2">
                  <.icon_button
                    size="lg"
                    id={"#{@id}-decrement-#{line_item.id}"}
                    type="button"
                    class="phx-click-loading:opacity-50"
                    phx-click="decrement_line_item"
                    phx-value-id={line_item.id}
                    phx-target={@myself}
                    aria_label={~t"Decrement"}
                  >
                    <.icon class="h-4 w-4" name="hero-minus-mini" />
                  </.icon_button>
                  <span class="tabular-nums">{line_item.quantity}</span>
                  <.icon_button
                    size="lg"
                    id={"#{@id}-increment-#{line_item.id}"}
                    type="button"
                    class="phx-click-loading:opacity-50"
                    phx-click="increment_line_item"
                    phx-value-id={line_item.id}
                    phx-target={@myself}
                    aria_label={~t"Increment"}
                  >
                    <.icon class="h-4 w-4" name="hero-plus-mini" />
                  </.icon_button>
                </div>
                <.icon_button
                  size="lg"
                  type="button"
                  id={"#{@id}-remove-#{line_item.id}"}
                  class="ml-auto phx-click-loading:opacity-50"
                  phx-click="tap_remove"
                  phx-value-id={line_item.id}
                  phx-target={@myself}
                  aria_label={~t"Remove"}
                >
                  <.icon name="hero-trash" class="h-4 w-4" />
                </.icon_button>
              </div>
              <p :if={@refused[line_item.id]} role="alert" class="text-error text-sm">
                {@refused[line_item.id]}
              </p>
              <%!-- Asked in the page, not with data-confirm: iOS Safari can refuse window.confirm
                   inside the drawer's modal dialog, which reads as Cancel and leaves the bin dead. --%>
              <div
                :if={@asking_to_remove == line_item.id and asks_before_removing?(@order, @typed_details?)}
                id={"#{@id}-ask-remove-#{line_item.id}"}
                role="alert"
                class="flex flex-col gap-3 text-sm"
              >
                <p>{~t"This empties your cart and clears the details you've entered. Continue?"}</p>
                <div class="flex flex-row gap-2">
                  <.button
                    id={"#{@id}-confirm-remove-#{line_item.id}"}
                    type="button"
                    size="sm"
                    variant="destructive"
                    phx-click="remove_item"
                    phx-value-id={line_item.id}
                    phx-target={@myself}
                  >
                    {~t"Remove"}
                  </.button>
                  <.button
                    type="button"
                    size="sm"
                    phx-click="keep_item"
                    phx-target={@myself}
                    phx-mounted={JS.focus()}
                  >
                    {~t"Cancel"}
                  </.button>
                </div>
              </div>

              <div :if={line_item.is_card} class="text-base-content/70 flex justify-end">
                <.icon_button
                  size="lg"
                  type="button"
                  id={"#{@id}-remove-#{line_item.id}"}
                  class="phx-click-loading:opacity-50"
                  phx-click="remove_item"
                  phx-value-id={line_item.id}
                  phx-target={@myself}
                  aria_label={~t"Remove"}
                >
                  <.icon name="hero-trash" class="h-4 w-4" />
                </.icon_button>
              </div>
            </div>
          </li>
        </ul>
      <% else %>
        <div class="flex flex-col items-center gap-5 py-10 text-center">
          <%!-- The closed dialog isn't rendered, so the bloom replays each time the drawer opens.
               It wraps the flower so the bloom's fill doesn't freeze the hover turn. --%>
          <span class="flower-bloom-soft [animation-delay:250ms]">
            <.flower name="flower-30" class="text-primary/70 h-20 w-20" />
          </span>
          <p class="font-serif text-lg">{~t"Your cart is empty."}</p>
          <.button navigate={~q"/#{language}/store"} phx-click={JS.exec("phx-hide", to: "#cart-drawer")}>
            {~t"Browse the store"}
          </.button>
        </div>
      <% end %>
    </div>
    """
  end

  attr :line_item, :map, required: true

  defp card_image(assigns) do
    ~H"""
    <.image
      src={@line_item.product_image_slug}
      alt={"Image of #{@line_item.product_name}"}
      width={120}
      height={120}
      sizes="80px"
      crop_type="fit"
      quality={90}
      loading="eager"
      class="h-16 w-16 object-contain sm:h-20 sm:w-20"
    />
    """
  end

  @impl true
  def handle_event("remove_item", %{"id" => id}, socket) do
    Orders.remove_line_item(socket.assigns.order, id)
    {:noreply, assign(socket, :asking_to_remove, nil)}
  end

  # Decided here rather than when the bin rendered: a checkout field sends what was typed on blur, which the
  # tap on the bin causes, so its change arrives just before this event.
  def handle_event("tap_remove", %{"id" => id} = params, socket) do
    if asks_before_removing?(socket.assigns.order, socket.assigns.typed_details?),
      do: {:noreply, assign(socket, :asking_to_remove, id)},
      else: handle_event("remove_item", params, socket)
  end

  def handle_event("keep_item", _params, socket) do
    {:noreply, assign(socket, :asking_to_remove, nil)}
  end

  def handle_event("increment_line_item", %{"id" => id}, socket) do
    with %{} = item <- line_item(socket.assigns.order, id),
         {:error, %Ash.Error.Invalid{errors: [%{message: message} | _]}} <- Orders.increment_line_item(item) do
      {:noreply, assign(socket, :refused, %{id => message})}
    else
      _ -> {:noreply, assign(socket, :refused, %{})}
    end
  end

  def handle_event("decrement_line_item", %{"id" => id}, socket) do
    if item = line_item(socket.assigns.order, id), do: Orders.decrement_line_item(item)
    {:noreply, assign(socket, :refused, %{})}
  end

  # Removing the one item restarts checkout, so ask only when that would lose something the customer filled in.
  defp asks_before_removing?(order, typed_details?) do
    order.one_item_left? and (order.checkout_details_saved? or typed_details?)
  end

  # Looked up on the session's own order, so a client can't adjust another cart's items,
  # and an item removed in another tab is ignored.
  defp line_item(order, id), do: Enum.find(order.line_items, &(&1.id == id))
end
