defmodule EdenflowersWeb.CartDrawerComponent do
  use EdenflowersWeb, :live_component

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

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
            class="translate-y-3 opacity-0"
            phx-click={JS.exec("phx-hide", to: "#cart-drawer")}
            phx-mounted={entrance_transition()}
          >
            {~t"Checkout"}
          </.button>

          <div
            :if={Enum.any?(@order.line_items)}
            class="translate-y-3 opacity-0"
            phx-mounted={entrance_transition()}
          >
            <.live_component
              id="cart-drawer-promo"
              module={EdenflowersWeb.PromoCodeComponent}
              order={@order}
              current_user={@current_user}
            />
          </div>
        </div>
      </.drawer>
    </div>
    """
  end

  # Shared with the line-item row entrance in LineItemsComponent — coordinates the
  # fade-in of Checkout button + Promo component when the cart transitions from empty
  # to one item. phx-mounted only fires on newly inserted nodes, so subsequent adds
  # (which don't re-mount these) skip the animation automatically.
  defp entrance_transition do
    JS.transition(
      {"transition-all duration-200 ease-out", "opacity-0 translate-y-3", "opacity-100 translate-y-0"},
      time: 200
    )
  end
end
