defmodule EdenflowersWeb.LineItemsComponent do
  @moduledoc """
  Renders line items belonging to either a Cart (mutable, with quantity
  controls) or an Order (read-only snapshot).

  Pass `cart` for the in-flight checkout flow; pass `order` for the placed
  order confirmation/account view. Exactly one must be provided.
  """
  use EdenflowersWeb, :live_component

  alias Edenflowers.Store.CartLineItem

  attr :id, :string, required: true
  attr :cart, :any, default: nil
  attr :order, :any, default: nil

  def render(assigns) do
    assigns = assign(assigns, :line_items, line_items_for(assigns))
    assigns = assign(assigns, :editable, not is_nil(assigns.cart))

    ~H"""
    <div id={@id}>
      <%= if Enum.any?(@line_items) do %>
        <ul class="flex flex-col gap-2">
          <li :for={line_item <- @line_items} class="flex flex-row gap-4 text-sm">
            <img
              class="h-18 w-18 rounded"
              src={line_item.product_image_slug |> Imgproxy.new() |> Imgproxy.resize(144, 144, type: "fill") |> to_string()}
              alt={"Image of #{line_item.product_name}"}
            />

            <div class="flex flex-1 flex-row justify-between">
              <div class="flex flex-col gap-2">
                <span>{line_item.product_name}</span>

                <div :if={@editable and not line_item.is_card} class="flex flex-row items-center gap-2">
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

                <div :if={not @editable and not line_item.is_card} class="text-base-content/60">
                  ×{line_item.quantity}
                </div>
              </div>

              <div class="flex flex-col items-end gap-2">
                <span>{Edenflowers.Utils.format_money(line_item.line_subtotal)}</span>
                <button
                  :if={@editable and not line_item.is_card}
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
        <p>{~t"Your cart is empty."}</p>
      <% end %>
    </div>
    """
  end

  def handle_event("remove_item", %{"id" => id}, socket) do
    CartLineItem.remove_item(id)
    {:noreply, socket}
  end

  def handle_event("increment_line_item", %{"id" => id}, socket) do
    CartLineItem.increment_quantity(id)
    {:noreply, socket}
  end

  def handle_event("decrement_line_item", %{"id" => id}, socket) do
    CartLineItem.decrement_quantity(id)
    {:noreply, socket}
  end

  defp line_items_for(%{cart: %{line_items: items}}) when is_list(items), do: items
  defp line_items_for(%{order: %{line_items: items}}) when is_list(items), do: items
  defp line_items_for(_), do: []
end
