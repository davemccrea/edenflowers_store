defmodule EdenflowersWeb.CartDrawerComponent do
  use EdenflowersWeb, :live_component

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  defp checkout_cta(state) when state in [:gift_options, :delivery, :payment], do: ~t"Continue Checkout"
  defp checkout_cta(_), do: ~t"Checkout"

  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.drawer
        id="cart-drawer"
        placement="right"
        label={gettext("Shopping cart")}
        class="bg-base-200 border-l-1 w-[80vw] flex h-full flex-col sm:w-[25rem]"
      >
        <header class="flex flex-row items-center justify-between pt-8 pr-4 pl-8">
          <h1 class="section-title">
            <%= if not is_nil(@order.total_items_in_cart) do %>
              {~t"Cart"} ({@order.total_items_in_cart})
            <% else %>
              {~t"Cart"}
            <% end %>
          </h1>

          <.icon_button aria_label={~t"Close cart"} phx-click={JS.exec("phx-hide", to: "#cart-drawer")}>
            <.icon name="hero-x-mark" class="h-6 w-6 hover:text-base-content/60" />
          </.icon_button>
        </header>

        <div class="flex flex-1 flex-col gap-6 overflow-y-auto p-8">
          <.live_component
            id="cart-line-items"
            module={EdenflowersWeb.LineItemsComponent}
            order={@order}
            link_product={true}
          />

          <.button
            :if={Enum.any?(@order.line_items)}
            navigate={~p"/checkout"}
            variant="primary"
            phx-click={JS.exec("phx-hide", to: "#cart-drawer")}
          >
            {checkout_cta(@order.state)}
          </.button>

          <.live_component
            :if={Enum.any?(@order.line_items)}
            id="cart-drawer-promo"
            module={EdenflowersWeb.PromoCodeComponent}
            order={@order}
            current_user={@current_user}
          />
        </div>
      </.drawer>
    </div>
    """
  end
end
