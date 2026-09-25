defmodule EdenflowersWeb.Cart.LineItems do
  use EdenflowersWeb, :live_component

  alias Edenflowers.Orders

  attr :id, :string, required: true
  attr :order, :any, required: true
  attr :link_product, :boolean, default: false

  def render(assigns) do
    ~H"""
    <div id={@id}>
      <%= if Enum.any?(@order.line_items) do %>
        <ul class="flex flex-col gap-5">
          <li :for={line_item <- @order.line_items} class="flex flex-row gap-3 text-base sm:gap-4">
            <%= if @link_product and not line_item.is_card do %>
              <.link
                navigate={~p"/product/#{line_item.product_id}"}
                class="shrink-0 transition-opacity hover:opacity-70"
              >
                <.image
                  src={line_item.product_image_slug}
                  alt={"Image of #{line_item.product_name}"}
                  width={80}
                  height={80}
                  sizes="80px"
                  class="h-16 w-16 object-cover sm:h-20 sm:w-20"
                />
              </.link>
            <% else %>
              <.image
                src={line_item.product_image_slug}
                alt={"Image of #{line_item.product_name}"}
                width={80}
                height={80}
                sizes="80px"
                class="h-16 w-16 object-cover sm:h-20 sm:w-20"
              />
            <% end %>

            <div class="flex min-w-0 flex-1 flex-col gap-2">
              <div class="flex flex-row justify-between gap-3">
                <div class="flex min-w-0 flex-col gap-0.5 break-words">
                  <%= if @link_product and not line_item.is_card do %>
                    <.link
                      navigate={~p"/product/#{line_item.product_id}"}
                      class="link-underline-hover"
                    >
                      {line_item.product_name}
                    </.link>
                  <% else %>
                    <span>{line_item.product_name}</span>
                  <% end %>
                  <span :if={line_item.variant_size} class="font-serif text-base-content/65 text-sm italic leading-none">
                    {String.capitalize(to_string(line_item.variant_size))}
                  </span>
                </div>
                <span class="shrink-0 tabular-nums">{Edenflowers.Format.currency(line_item.subtotal, @order.locale)}</span>
              </div>

              <%!-- gap-2 and the 4rem mobile thumbnail are load-bearing: three 3rem
              buttons only fit on one line down to 320px with this budget. --%>
              <div :if={not line_item.is_card} class="text-base-content/70 flex flex-row items-center justify-between gap-2">
                <div class="flex flex-row items-center gap-2">
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
                  class="phx-click-loading:opacity-50"
                  phx-click="remove_item"
                  data-confirm={
                    last_non_card_item?(@order) &&
                      ~t"Removing this empties your cart and clears the checkout details you've entered. Continue?"
                  }
                  phx-value-id={line_item.id}
                  phx-target={@myself}
                  aria_label={~t"Remove"}
                >
                  <.icon name="hero-trash" class="h-4 w-4" />
                </.icon_button>
              </div>

              <div :if={line_item.is_card} class="text-base-content/70 flex justify-end">
                <.icon_button
                  size="lg"
                  type="button"
                  id={"#{@id}-remove-#{line_item.id}"}
                  class="phx-click-loading:opacity-50"
                  phx-click="remove_card"
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
          <.flower name="flower-30" class="text-primary/70 h-20 w-20" />
          <p class="font-serif text-lg">{~t"Your cart is empty."}</p>
          <.button navigate={~p"/store"} phx-click={JS.exec("phx-hide", to: "#cart-drawer")}>
            {~t"Browse the store"}
          </.button>
        </div>
      <% end %>
    </div>
    """
  end

  # Removing the last non-card item restarts checkout, which blanks every
  # field the customer has entered. See Orders.Order.Changes.RemoveLineItem.
  defp last_non_card_item?(order) do
    Enum.count(order.line_items, &(not &1.is_card)) == 1
  end

  def handle_event("remove_item", %{"id" => id}, socket) do
    Orders.remove_line_item(socket.assigns.order, id)
    {:noreply, socket}
  end

  # Not `remove_item`: removing the card also clears the card message.
  def handle_event("remove_card", _, socket) do
    Orders.remove_card(socket.assigns.order)
    {:noreply, socket}
  end

  def handle_event("increment_line_item", %{"id" => id}, socket) do
    Orders.increment_line_item(socket.assigns.order, id)
    {:noreply, socket}
  end

  def handle_event("decrement_line_item", %{"id" => id}, socket) do
    Orders.decrement_line_item(socket.assigns.order, id)
    {:noreply, socket}
  end
end
