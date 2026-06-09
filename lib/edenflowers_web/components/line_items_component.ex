defmodule EdenflowersWeb.LineItemsComponent do
  use EdenflowersWeb, :live_component

  alias Edenflowers.Orders.Order

  attr :id, :string, required: true
  attr :order, :any, required: true
  attr :link_product, :boolean, default: false

  def render(assigns) do
    ~H"""
    <div id={@id}>
      <%= if Enum.any?(@order.line_items) do %>
        <ul class="flex flex-col gap-5">
          <li :for={line_item <- @order.line_items} class="flex flex-row gap-4 text-base">
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
                  class="h-20 w-20 object-cover"
                />
              </.link>
            <% else %>
              <.image
                src={line_item.product_image_slug}
                alt={"Image of #{line_item.product_name}"}
                width={80}
                height={80}
                sizes="80px"
                class="h-20 w-20 object-cover"
              />
            <% end %>

            <div class="flex flex-1 flex-col gap-2">
              <div class="flex flex-row justify-between gap-3">
                <div class="flex flex-col gap-0.5">
                  <%= if @link_product and not line_item.is_card do %>
                    <.link
                      navigate={~p"/product/#{line_item.product_id}"}
                      class="link-underline-hover-nav"
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
                <span class="shrink-0 tabular-nums">{Edenflowers.Format.currency(line_item.subtotal)}</span>
              </div>

              <div :if={not line_item.is_card} class="text-base-content/70 flex flex-row items-center justify-between gap-3">
                <div class="flex flex-row items-center gap-3">
                  <button
                    id={"#{@id}-decrement-#{line_item.id}"}
                    type="button"
                    class="cursor-pointer p-1 hover:text-base-content phx-click-loading:opacity-50"
                    phx-click="decrement_line_item"
                    phx-value-id={line_item.id}
                    phx-target={@myself}
                    aria-label={~t"Decrement"}
                  >
                    <.icon class="h-4 w-4" name="hero-minus-mini" />
                  </button>
                  <span class="tabular-nums">{line_item.quantity}</span>
                  <button
                    id={"#{@id}-increment-#{line_item.id}"}
                    type="button"
                    class="cursor-pointer p-1 hover:text-base-content phx-click-loading:opacity-50"
                    phx-click="increment_line_item"
                    phx-value-id={line_item.id}
                    phx-target={@myself}
                    aria-label={~t"Increment"}
                  >
                    <.icon class="h-4 w-4" name="hero-plus-mini" />
                  </button>
                </div>
                <button
                  type="button"
                  id={"#{@id}-remove-#{line_item.id}"}
                  class="cursor-pointer p-1 hover:text-base-content phx-click-loading:opacity-50"
                  phx-click="remove_item"
                  phx-value-id={line_item.id}
                  phx-target={@myself}
                  aria-label={~t"Remove"}
                >
                  <.icon name="hero-trash" class="h-4 w-4" />
                </button>
              </div>

              <div :if={line_item.is_card} class="text-base-content/70 flex justify-end">
                <button
                  type="button"
                  id={"#{@id}-remove-#{line_item.id}"}
                  class="cursor-pointer p-1 hover:text-base-content phx-click-loading:opacity-50"
                  phx-click="remove_item"
                  phx-value-id={line_item.id}
                  phx-target={@myself}
                  aria-label={~t"Remove"}
                >
                  <.icon name="hero-trash" class="h-4 w-4" />
                </button>
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

  def handle_event("remove_item", %{"id" => id}, socket) do
    Order.remove_line_item(socket.assigns.order, id)
    {:noreply, socket}
  end

  def handle_event("increment_line_item", %{"id" => id}, socket) do
    Order.increment_line_item(socket.assigns.order, id)
    {:noreply, socket}
  end

  def handle_event("decrement_line_item", %{"id" => id}, socket) do
    Order.decrement_line_item(socket.assigns.order, id)
    {:noreply, socket}
  end
end
