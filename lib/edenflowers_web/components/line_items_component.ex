defmodule EdenflowersWeb.LineItemsComponent do
  use EdenflowersWeb, :live_component

  alias Edenflowers.Store.Order

  attr :id, :string, required: true
  attr :order, :any, required: true

  def render(assigns) do
    ~H"""
    <div id={@id}>
      <%= if Enum.any?(@order.line_items) do %>
        <ul class="flex flex-col gap-2">
          <li :for={line_item <- @order.line_items} class="flex flex-row gap-4 text-sm">
            <img
              class="h-18 w-18 rounded"
              src={line_item.product_image_slug |> Imgproxy.new() |> Imgproxy.resize(144, 144, type: "fill") |> to_string()}
              alt={"Image of #{line_item.product_name}"}
            />

            <div class="flex flex-1 flex-row justify-between">
              <div class="flex flex-col gap-2">
                <span>{line_item.product_name}</span>

                <div :if={not line_item.is_card} class="flex flex-row items-center gap-2">
                  <button
                    id={"#{@id}-decrement-#{line_item.id}"}
                    type="button"
                    class="btn btn-xs btn-square phx-click-loading:btn-disabled"
                    phx-click="decrement_line_item"
                    phx-value-id={line_item.id}
                    phx-target={@myself}
                    aria-label={~t"Decrement"}
                  >
                    <.icon class="h-4 w-4" name="hero-minus-mini" />
                  </button>
                  <span>{line_item.quantity}</span>
                  <button
                    id={"#{@id}-increment-#{line_item.id}"}
                    type="button"
                    class="btn btn-xs btn-square phx-click-loading:btn-disabled"
                    phx-click="increment_line_item"
                    phx-value-id={line_item.id}
                    phx-target={@myself}
                    aria-label={~t"Increment"}
                  >
                    <.icon class="h-4 w-4" name="hero-plus-mini" />
                  </button>
                </div>
              </div>

              <div class="flex flex-col items-end gap-2">
                <span>{Edenflowers.Utils.format_money(line_item.line_subtotal)}</span>
                <button
                  :if={not line_item.is_card}
                  type="button"
                  id={"#{@id}-remove-#{line_item.id}"}
                  class="btn btn-square btn-ghost btn-xs phx-click-loading:btn-disabled"
                  phx-click="remove_item"
                  phx-value-id={line_item.id}
                  phx-target={@myself}
                  aria-label={~t"Remove"}
                >
                  <.icon name="hero-trash" class="text-error h-4 w-4" />
                </button>
              </div>
            </div>
          </li>
        </ul>
      <% else %>
        <div class="flex flex-col items-center gap-5 py-10 text-center">
          <.flower seed="cart-empty" class="text-primary/70 h-20 w-20" />
          <p class="font-serif text-lg">{~t"Your cart is empty."}</p>
          <.button navigate={~p"/store"}>{~t"Browse the store"}</.button>
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
